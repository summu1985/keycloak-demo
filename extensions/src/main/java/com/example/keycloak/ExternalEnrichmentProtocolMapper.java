package com.example.keycloak;

import org.jboss.logging.Logger;
import org.keycloak.models.ClientSessionContext;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.ProtocolMapperModel;
import org.keycloak.models.RoleModel;
import org.keycloak.models.UserModel;
import org.keycloak.models.UserSessionModel;
import org.keycloak.protocol.oidc.mappers.AbstractOIDCProtocolMapper;
import org.keycloak.protocol.oidc.mappers.OIDCAccessTokenMapper;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.representations.IDToken;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;
import java.util.stream.Collectors;

/**
 * Calls an external enrichment API while an access token is being created.
 *
 * Request fields:
 *   userid, userType, roles
 *
 * The complete response is added as a nested claim (external_enrichment by
 * default). This avoids colliding with Keycloak's standard role claims.
 */
public final class ExternalEnrichmentProtocolMapper extends AbstractOIDCProtocolMapper
        implements OIDCAccessTokenMapper {

    public static final String PROVIDER_ID = "external-enrichment-protocol-mapper";
    private static final Logger LOG = Logger.getLogger(ExternalEnrichmentProtocolMapper.class);

    private static final String CFG_URL = "enrichment.api.url";
    private static final String CFG_TIMEOUT_MS = "enrichment.timeout.ms";
    private static final String CFG_FAIL_ON_ERROR = "enrichment.fail.on.error";
    private static final String CFG_CLAIM_NAME = "claim.name";

    private static final Pattern STRING_FIELD =
            Pattern.compile("\\\"%s\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");
    private static final Pattern BOOLEAN_FIELD =
            Pattern.compile("\\\"%s\\\"\\s*:\\s*(true|false)");
    private static final Pattern ROLES_FIELD =
            Pattern.compile("\\\"roles\\\"\\s*:\\s*\\[(.*?)]", Pattern.DOTALL);
    private static final Pattern ARRAY_STRING = Pattern.compile("\\\"([^\\\"]+)\\\"");

    private static final List<ProviderConfigProperty> CONFIG_PROPERTIES;

    static {
        ProviderConfigProperty url = new ProviderConfigProperty();
        url.setName(CFG_URL);
        url.setLabel("Enrichment API URL");
        url.setHelpText("HTTP POST endpoint receiving userid, userType and roles.");
        url.setType(ProviderConfigProperty.STRING_TYPE);
        url.setDefaultValue("http://mock-enrichment-api:8080/enrich");

        ProviderConfigProperty timeout = new ProviderConfigProperty();
        timeout.setName(CFG_TIMEOUT_MS);
        timeout.setLabel("Timeout in milliseconds");
        timeout.setHelpText("Maximum time allowed for the enrichment API call.");
        timeout.setType(ProviderConfigProperty.STRING_TYPE);
        timeout.setDefaultValue("2000");

        ProviderConfigProperty fail = new ProviderConfigProperty();
        fail.setName(CFG_FAIL_ON_ERROR);
        fail.setLabel("Fail token issuance on API error");
        fail.setHelpText("When true, token issuance fails if enrichment is unavailable. Demo default is false.");
        fail.setType(ProviderConfigProperty.BOOLEAN_TYPE);
        fail.setDefaultValue("false");

        ProviderConfigProperty claim = new ProviderConfigProperty();
        claim.setName(CFG_CLAIM_NAME);
        claim.setLabel("Token claim name");
        claim.setHelpText("Nested claim that receives the enrichment API response.");
        claim.setType(ProviderConfigProperty.STRING_TYPE);
        claim.setDefaultValue("external_enrichment");

        CONFIG_PROPERTIES = List.of(url, timeout, fail, claim);
    }

    @Override
    public String getDisplayCategory() {
        return "Token mapper";
    }

    @Override
    public String getDisplayType() {
        return "External token enrichment";
    }

    @Override
    public String getHelpText() {
        return "Calls a configured API with userid, userType and realm roles, then places the returned fields in a nested token claim.";
    }

    @Override
    public List<ProviderConfigProperty> getConfigProperties() {
        return CONFIG_PROPERTIES;
    }

    @Override
    public String getId() {
        return PROVIDER_ID;
    }

    @Override
    protected void setClaim(
            IDToken token,
            ProtocolMapperModel mappingModel,
            UserSessionModel userSession,
            KeycloakSession session,
            ClientSessionContext clientSessionCtx) {

        Map<String, String> config = mappingModel.getConfig() == null
                ? Map.of()
                : mappingModel.getConfig();

        String endpoint = config.getOrDefault(CFG_URL, "http://mock-enrichment-api:8080/enrich");
        int timeoutMs = parseInt(config.get(CFG_TIMEOUT_MS), 2000);
        boolean failOnError = Boolean.parseBoolean(config.getOrDefault(CFG_FAIL_ON_ERROR, "false"));
        String claimName = config.getOrDefault(CFG_CLAIM_NAME, "external_enrichment");

        UserModel user = userSession.getUser();
        String userId = user.getUsername();
        String userType = resolveUserType(userSession, user);
        List<String> roles = user.getRoleMappingsStream()
                .map(RoleModel::getName)
                .sorted()
                .collect(Collectors.toList());

        String requestBody = buildRequest(userId, userType, roles);

        try {
            HttpClient client = HttpClient.newBuilder()
                    .connectTimeout(Duration.ofMillis(timeoutMs))
                    .build();

            HttpRequest request = HttpRequest.newBuilder(URI.create(endpoint))
                    .timeout(Duration.ofMillis(timeoutMs))
                    .header("Content-Type", "application/json")
                    .POST(HttpRequest.BodyPublishers.ofString(requestBody, StandardCharsets.UTF_8))
                    .build();

            LOG.infof("Calling enrichment API for userid=%s userType=%s roles=%s", userId, userType, roles);
            HttpResponse<String> response = client.send(request, HttpResponse.BodyHandlers.ofString());

            if (response.statusCode() / 100 != 2) {
                throw new IllegalStateException("Enrichment API returned HTTP " + response.statusCode());
            }

            Map<String, Object> enrichment = parseResponse(response.body());
            token.getOtherClaims().put(claimName, enrichment);
            LOG.infof("External enrichment applied for userid=%s customKey=%s",
                    userId, enrichment.get("customKey"));
        } catch (Exception e) {
            LOG.errorf(e, "External enrichment failed for userid=%s", userId);
            if (failOnError) {
                throw new IllegalStateException("External token enrichment failed", e);
            }
            Map<String, Object> fallback = new LinkedHashMap<>();
            fallback.put("enrichmentApplied", false);
            fallback.put("error", "enrichment_service_unavailable");
            token.getOtherClaims().put(claimName, fallback);
        }
    }

    private static String resolveUserType(UserSessionModel session, UserModel user) {
        String note = session.getNote("derived_user_type");
        if (note != null && !note.isBlank()) {
            return note;
        }
        String attribute = user.getFirstAttribute("user_type");
        if (attribute != null && !attribute.isBlank()) {
            return attribute;
        }
        String username = user.getUsername().toLowerCase();
        if (username.startsWith("sp") || username.startsWith("p")) {
            return "employee";
        }
        if (username.matches("^\\d{10}$")) {
            return "customer";
        }
        return "internal";
    }

    private static String buildRequest(String userId, String userType, List<String> roles) {
        return "{" +
                "\"userid\":\"" + jsonEscape(userId) + "\"," +
                "\"userType\":\"" + jsonEscape(userType) + "\"," +
                "\"roles\":[" + roles.stream()
                        .map(role -> "\"" + jsonEscape(role) + "\"")
                        .collect(Collectors.joining(",")) + "]" +
                "}";
    }

    private static Map<String, Object> parseResponse(String body) {
        Map<String, Object> result = new LinkedHashMap<>();
        result.put("userid", stringField(body, "userid"));
        result.put("userType", stringField(body, "userType"));
        result.put("roles", roles(body));
        result.put("customKey", stringField(body, "customKey"));
        result.put("enrichmentApplied", booleanField(body, "enrichmentApplied"));
        return result;
    }

    private static String stringField(String body, String name) {
        Matcher matcher = Pattern.compile(
                String.format(STRING_FIELD.pattern(), Pattern.quote(name))).matcher(body);
        return matcher.find() ? matcher.group(1) : null;
    }

    private static boolean booleanField(String body, String name) {
        Matcher matcher = Pattern.compile(
                String.format(BOOLEAN_FIELD.pattern(), Pattern.quote(name))).matcher(body);
        return matcher.find() && Boolean.parseBoolean(matcher.group(1));
    }

    private static List<String> roles(String body) {
        Matcher field = ROLES_FIELD.matcher(body);
        if (!field.find()) {
            return List.of();
        }
        List<String> roles = new ArrayList<>();
        Matcher values = ARRAY_STRING.matcher(field.group(1));
        while (values.find()) {
            roles.add(values.group(1));
        }
        return roles;
    }

    private static int parseInt(String value, int fallback) {
        try {
            return value == null ? fallback : Integer.parseInt(value);
        } catch (NumberFormatException e) {
            return fallback;
        }
    }

    private static String jsonEscape(String value) {
        if (value == null) {
            return "";
        }
        return value
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }
}
