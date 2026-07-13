package com.example.keycloak;

import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.Authenticator;
import org.keycloak.models.AuthenticatorConfigModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Duration;
import java.time.Instant;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Demo-only passwordless mobile OTP authenticator.
 *
 * For a 10-digit username, this authenticator calls a mock SMS API, stores only
 * a SHA-256 hash of the returned OTP in the authentication session, displays an
 * OTP form, and verifies the submitted code. For all other usernames it returns
 * attempted(), allowing an alternative Password Form execution to authenticate.
 */
public final class MobileOtpAuthenticator implements Authenticator {
    private static final Pattern MOBILE = Pattern.compile("^\\d{10}$");
    private static final Pattern OTP_JSON = Pattern.compile("\\\"otp\\\"\\s*:\\s*\\\"(\\d{4,8})\\\"");
    private static final HttpClient HTTP = HttpClient.newBuilder()
            .connectTimeout(Duration.ofSeconds(2))
            .build();

    private static final String NOTE_HASH = "demo_mobile_otp_hash";
    private static final String NOTE_EXPIRES = "demo_mobile_otp_expires";
    private static final String NOTE_ATTEMPTS = "demo_mobile_otp_attempts";
    private static final String NOTE_SENT = "demo_mobile_otp_sent";

    @Override
    public void authenticate(AuthenticationFlowContext context) {
        UserModel user = context.getUser();
        if (user == null) {
            context.failure(AuthenticationFlowError.UNKNOWN_USER);
            return;
        }

        String mobile = user.getUsername();
        if (!MOBILE.matcher(mobile).matches()) {
            context.attempted();
            return;
        }

        if (isExistingOtpUsable(context)) {
            challenge(context, mobile, null);
            return;
        }

        try {
            String otp = requestOtp(context, mobile);
            int ttl = intConfig(context, "otp.ttl.seconds", 120);
            context.getAuthenticationSession().setAuthNote(NOTE_HASH, sha256(otp));
            context.getAuthenticationSession().setAuthNote(
                    NOTE_EXPIRES, String.valueOf(Instant.now().getEpochSecond() + ttl));
            context.getAuthenticationSession().setAuthNote(NOTE_ATTEMPTS, "0");
            context.getAuthenticationSession().setAuthNote(NOTE_SENT, "true");
            challenge(context, mobile, null);
        } catch (Exception e) {
            Response error = context.form()
                    .setError("Unable to send the OTP. Please try again.")
                    .createErrorPage(Response.Status.SERVICE_UNAVAILABLE);
            context.failureChallenge(AuthenticationFlowError.INTERNAL_ERROR, error);
        }
    }

    @Override
    public void action(AuthenticationFlowContext context) {
        UserModel user = context.getUser();
        if (user == null || !MOBILE.matcher(user.getUsername()).matches()) {
            context.attempted();
            return;
        }

        MultivaluedMap<String, String> form = context.getHttpRequest().getDecodedFormParameters();
        String entered = form.getFirst("otp");

        int attempts = parseInt(context.getAuthenticationSession().getAuthNote(NOTE_ATTEMPTS), 0) + 1;
        int maxAttempts = intConfig(context, "otp.max.attempts", 3);
        context.getAuthenticationSession().setAuthNote(NOTE_ATTEMPTS, String.valueOf(attempts));

        if (isExpired(context)) {
            clearOtp(context);
            Response response = context.form()
                    .setError("The OTP has expired. Restart login to request a new OTP.")
                    .createForm("mobile-otp.ftl");
            context.failureChallenge(AuthenticationFlowError.EXPIRED_CODE, response);
            return;
        }

        String expectedHash = context.getAuthenticationSession().getAuthNote(NOTE_HASH);
        boolean valid = entered != null && expectedHash != null &&
                MessageDigest.isEqual(expectedHash.getBytes(StandardCharsets.UTF_8),
                        sha256(entered.trim()).getBytes(StandardCharsets.UTF_8));

        if (!valid) {
            if (attempts >= maxAttempts) {
                clearOtp(context);
                Response response = context.form()
                        .setError("Maximum OTP attempts exceeded. Restart login.")
                        .createErrorPage(Response.Status.UNAUTHORIZED);
                context.failureChallenge(AuthenticationFlowError.INVALID_CREDENTIALS, response);
            } else {
                challenge(context, user.getUsername(),
                        "Invalid OTP. " + (maxAttempts - attempts) + " attempt(s) remaining.");
            }
            return;
        }

        clearOtp(context);
        context.getAuthenticationSession().setUserSessionNote("derived_user_type", "customer");
        context.success();
    }

    private static void challenge(AuthenticationFlowContext context, String mobile, String error) {
        var form = context.form()
                .setAttribute("mobile", mask(mobile))
                .setAttribute("username", mobile);
        if (error != null) form.setError(error);
        context.challenge(form.createForm("mobile-otp.ftl"));
    }

    private static String requestOtp(AuthenticationFlowContext context, String mobile) throws Exception {
        String base = config(context).getOrDefault("sms.api.url", "http://mock-sms-api:8080/send");
        String separator = base.contains("?") ? "&" : "?";
        URI uri = URI.create(base + separator + "mobile=" +
                URLEncoder.encode(mobile, StandardCharsets.UTF_8));
        HttpRequest request = HttpRequest.newBuilder(uri)
                .timeout(Duration.ofSeconds(3))
                .GET()
                .build();
        HttpResponse<String> response = HTTP.send(request, HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() / 100 != 2) {
            throw new IllegalStateException("SMS API returned " + response.statusCode());
        }
        Matcher matcher = OTP_JSON.matcher(response.body());
        if (!matcher.find()) throw new IllegalStateException("SMS API response has no OTP");
        return matcher.group(1);
    }

    private static boolean isExistingOtpUsable(AuthenticationFlowContext context) {
        return "true".equals(context.getAuthenticationSession().getAuthNote(NOTE_SENT)) && !isExpired(context);
    }

    private static boolean isExpired(AuthenticationFlowContext context) {
        long expires = parseLong(context.getAuthenticationSession().getAuthNote(NOTE_EXPIRES), 0);
        return expires == 0 || Instant.now().getEpochSecond() > expires;
    }

    private static void clearOtp(AuthenticationFlowContext context) {
        context.getAuthenticationSession().removeAuthNote(NOTE_HASH);
        context.getAuthenticationSession().removeAuthNote(NOTE_EXPIRES);
        context.getAuthenticationSession().removeAuthNote(NOTE_ATTEMPTS);
        context.getAuthenticationSession().removeAuthNote(NOTE_SENT);
    }

    private static Map<String, String> config(AuthenticationFlowContext context) {
        AuthenticatorConfigModel model = context.getAuthenticatorConfig();
        return model == null || model.getConfig() == null ? Map.of() : model.getConfig();
    }

    private static int intConfig(AuthenticationFlowContext context, String key, int fallback) {
        return parseInt(config(context).get(key), fallback);
    }

    private static int parseInt(String value, int fallback) {
        try { return value == null ? fallback : Integer.parseInt(value); }
        catch (NumberFormatException e) { return fallback; }
    }

    private static long parseLong(String value, long fallback) {
        try { return value == null ? fallback : Long.parseLong(value); }
        catch (NumberFormatException e) { return fallback; }
    }

    private static String sha256(String value) {
        try {
            byte[] hash = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            return java.util.HexFormat.of().formatHex(hash);
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    private static String mask(String mobile) {
        return mobile.length() < 4 ? mobile : "******" + mobile.substring(mobile.length() - 4);
    }

    @Override public boolean requiresUser() { return true; }
    @Override public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) { return true; }
    @Override public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) { }
    @Override public void close() { }
}
