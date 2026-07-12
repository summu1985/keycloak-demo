package com.example.keycloak;

import org.keycloak.Config;
import org.keycloak.authentication.Authenticator;
import org.keycloak.authentication.AuthenticatorFactory;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;

import java.util.List;

public final class UsernamePatternGuardAuthenticatorFactory implements AuthenticatorFactory {
    public static final String ID = "username-pattern-backend-guard";
    private static final Authenticator SINGLETON = new UsernamePatternGuardAuthenticator();
    @Override public String getId() { return ID; }
    @Override public String getDisplayType() { return "Username Pattern / Backend Guard"; }
    @Override public String getReferenceCategory() { return "username-pattern"; }
    @Override public boolean isConfigurable() { return false; }
    @Override public AuthenticationExecutionModel.Requirement[] getRequirementChoices() { return new AuthenticationExecutionModel.Requirement[]{AuthenticationExecutionModel.Requirement.REQUIRED, AuthenticationExecutionModel.Requirement.DISABLED}; }
    @Override public boolean isUserSetupAllowed() { return false; }
    @Override public String getHelpText() { return "Enforces LDAP for sp*/p* users and local Keycloak storage for 10-digit and other users; derives user type."; }
    @Override public List<ProviderConfigProperty> getConfigProperties() { return List.of(); }
    @Override public Authenticator create(KeycloakSession session) { return SINGLETON; }
    @Override public void init(Config.Scope config) { }
    @Override public void postInit(KeycloakSessionFactory factory) { }
    @Override public void close() { }
}
