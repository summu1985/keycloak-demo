package com.example.keycloak;

import jakarta.ws.rs.core.Response;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.Authenticator;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.UserModel;

import java.util.regex.Pattern;

public final class UsernamePatternGuardAuthenticator implements Authenticator {
    private static final Pattern MOBILE = Pattern.compile("^\\d{10}$");

    @Override public void authenticate(AuthenticationFlowContext context) {
        UserModel user = context.getUser();
        if (user == null) { context.failure(AuthenticationFlowError.UNKNOWN_USER); return; }
        String username = user.getUsername().toLowerCase();
        boolean federated = user.getFederationLink() != null;
        String userType;
        boolean valid;
        if (username.startsWith("sp") || username.startsWith("p")) {
            userType = "employee"; valid = federated;
        } else if (MOBILE.matcher(username).matches()) {
            userType = "customer"; valid = !federated;
        } else {
            userType = "internal"; valid = !federated;
        }
        if (!valid) {
            Response challenge = context.form().setError("User is not stored in the authentication backend required by the username pattern").createErrorPage(Response.Status.UNAUTHORIZED);
            context.failureChallenge(AuthenticationFlowError.INVALID_USER, challenge); return;
        }
        context.getAuthenticationSession().setUserSessionNote("derived_user_type", userType);
        context.success();
    }
    @Override public void action(AuthenticationFlowContext context) { context.success(); }
    @Override public boolean requiresUser() { return true; }
    @Override public boolean configuredFor(KeycloakSession session, RealmModel realm, UserModel user) { return true; }
    @Override public void setRequiredActions(KeycloakSession session, RealmModel realm, UserModel user) { }
    @Override public void close() { }
}
