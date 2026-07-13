package com.example.keycloak;

import org.keycloak.Config;
import org.keycloak.authentication.Authenticator;
import org.keycloak.authentication.AuthenticatorFactory;
import org.keycloak.models.AuthenticationExecutionModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.KeycloakSessionFactory;
import org.keycloak.provider.ProviderConfigProperty;

import java.util.List;

public final class MobileOtpAuthenticatorFactory implements AuthenticatorFactory {
    public static final String ID = "mobile-passwordless-otp";
    private static final Authenticator SINGLETON = new MobileOtpAuthenticator();
    private static final List<ProviderConfigProperty> CONFIG;

    static {
        ProviderConfigProperty url = new ProviderConfigProperty();
        url.setName("sms.api.url");
        url.setLabel("Mock/real SMS API URL");
        url.setHelpText("HTTP endpoint returning JSON such as {\"otp\":\"123456\"}. Demo default: http://mock-sms-api:8080/send");
        url.setType(ProviderConfigProperty.STRING_TYPE);
        url.setDefaultValue("http://mock-sms-api:8080/send");

        ProviderConfigProperty ttl = new ProviderConfigProperty();
        ttl.setName("otp.ttl.seconds");
        ttl.setLabel("OTP validity in seconds");
        ttl.setType(ProviderConfigProperty.STRING_TYPE);
        ttl.setDefaultValue("120");

        ProviderConfigProperty attempts = new ProviderConfigProperty();
        attempts.setName("otp.max.attempts");
        attempts.setLabel("Maximum OTP attempts");
        attempts.setType(ProviderConfigProperty.STRING_TYPE);
        attempts.setDefaultValue("3");

        CONFIG = List.of(url, ttl, attempts);
    }

    @Override public String getId() { return ID; }
    @Override public String getDisplayType() { return "Mobile Number Passwordless OTP"; }
    @Override public String getReferenceCategory() { return "mobile-otp"; }
    @Override public boolean isConfigurable() { return true; }
    @Override public AuthenticationExecutionModel.Requirement[] getRequirementChoices() {
        return new AuthenticationExecutionModel.Requirement[]{
                AuthenticationExecutionModel.Requirement.ALTERNATIVE,
                AuthenticationExecutionModel.Requirement.REQUIRED,
                AuthenticationExecutionModel.Requirement.DISABLED
        };
    }
    @Override public boolean isUserSetupAllowed() { return false; }
    @Override public String getHelpText() {
        return "For an existing 10-digit username, obtains an OTP from the configured SMS API and authenticates without a password. Non-mobile users are skipped.";
    }
    @Override public List<ProviderConfigProperty> getConfigProperties() { return CONFIG; }
    @Override public Authenticator create(KeycloakSession session) { return SINGLETON; }
    @Override public void init(Config.Scope config) { }
    @Override public void postInit(KeycloakSessionFactory factory) { }
    @Override public void close() { }
}
