package com.example.keycloak;

import org.keycloak.Config;
import org.keycloak.authentication.Authenticator;
import org.keycloak.authentication.AuthenticatorFactory;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;

import java.util.List;

public final class JitCustomerUsernameAuthenticatorFactory implements AuthenticatorFactory {
    public static final String ID = "jit-customer-username-form";
    private static final Authenticator SINGLETON = new JitCustomerUsernameAuthenticator();
    private static final List<ProviderConfigProperty> CONFIG;

    static {
        ProviderConfigProperty url = new ProviderConfigProperty();
        url.setName("customer.registry.url");
        url.setLabel("Customer registry base URL");
        url.setHelpText("Base endpoint followed by /{mobile}. Demo: http://mock-customer-registry:8080/customers/by-mobile");
        url.setType(ProviderConfigProperty.STRING_TYPE);
        url.setDefaultValue("http://mock-customer-registry:8080/customers/by-mobile");
        CONFIG = List.of(url);
    }

    @Override public String getId() { return ID; }
    @Override public String getDisplayType() { return "JIT Customer Username Form"; }
    @Override public String getReferenceCategory() { return "username"; }
    @Override public boolean isConfigurable() { return true; }
    @Override public AuthenticationExecutionModel.Requirement[] getRequirementChoices() {
        return new AuthenticationExecutionModel.Requirement[]{
                AuthenticationExecutionModel.Requirement.REQUIRED,
                AuthenticationExecutionModel.Requirement.DISABLED
        };
    }
    @Override public boolean isUserSetupAllowed() { return false; }
    @Override public String getHelpText() {
        return "Resolves normal users and validates 10-digit mobile users against a customer registry, creating eligible customers just in time.";
    }
    @Override public List<ProviderConfigProperty> getConfigProperties() { return CONFIG; }
    @Override public Authenticator create(KeycloakSession session) { return SINGLETON; }
    @Override public void init(Config.Scope config) { }
    @Override public void postInit(KeycloakSessionFactory factory) { }
    @Override public void close() { }
}
