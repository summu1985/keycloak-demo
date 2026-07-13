package com.example.keycloak;

import org.keycloak.models.ClientSessionContext;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.ProtocolMapperModel;
import org.keycloak.models.UserSessionModel;
import org.keycloak.protocol.oidc.mappers.AbstractOIDCProtocolMapper;
import org.keycloak.protocol.oidc.mappers.OIDCAccessTokenMapper;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.representations.IDToken;

import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

public final class ExternalEnrichmentProtocolMapper extends AbstractOIDCProtocolMapper implements OIDCAccessTokenMapper {
    public static final String PROVIDER_ID = "external-enrichment-mapper";
    private static final List<ProviderConfigProperty> CONFIG = new ArrayList<>();
    private static final HttpClient HTTP = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(2)).build();
    static {
        ProviderConfigProperty url = new ProviderConfigProperty(); url.setName("api.url"); url.setLabel("Enrichment API URL"); url.setType(ProviderConfigProperty.STRING_TYPE); url.setDefaultValue("http://token-enrichment-api:8080/enrich"); CONFIG.add(url);
        ProviderConfigProperty fail = new ProviderConfigProperty(); fail.setName("fail.closed"); fail.setLabel("Fail token issuance if API fails"); fail.setType(ProviderConfigProperty.BOOLEAN_TYPE); fail.setDefaultValue("true"); CONFIG.add(fail);
    }
    @Override public String getDisplayCategory() { return "Token mapper"; }
    @Override public String getDisplayType() { return "External Employee Enrichment"; }
    @Override public String getHelpText() { return "For employee usernames, calls an external API and adds user_id, user_type and enriched_roles claims."; }
    @Override public List<ProviderConfigProperty> getConfigProperties() { return CONFIG; }
    @Override public String getId() { return PROVIDER_ID; }

    @Override protected void setClaim(IDToken token, ProtocolMapperModel mappingModel, UserSessionModel userSession, KeycloakSession keycloakSession, ClientSessionContext clientSessionCtx) {
        String username = userSession.getUser().getUsername();
        String derived = userSession.getNote("derived_user_type");
        boolean employee = "employee".equals(derived) || username.toLowerCase().startsWith("sp") || username.toLowerCase().startsWith("p");
        if (!employee) return;
        String url = mappingModel.getConfig().getOrDefault("api.url", "http://token-enrichment-api:8080/enrich");
        boolean failClosed = Boolean.parseBoolean(mappingModel.getConfig().getOrDefault("fail.closed", "true"));
        try {
            HttpRequest req = HttpRequest.newBuilder(URI.create(url + "?username=" + java.net.URLEncoder.encode(username, java.nio.charset.StandardCharsets.UTF_8)))
                    .timeout(Duration.ofSeconds(3)).GET().build();
            HttpResponse<String> res = HTTP.send(req, HttpResponse.BodyHandlers.ofString());
            if (res.statusCode() / 100 != 2) throw new IllegalStateException("Enrichment API status " + res.statusCode());
            String body = res.body();
            token.getOtherClaims().put("user_id", extract(body, "userId"));
            token.getOtherClaims().put("user_type", extract(body, "userType"));
            token.getOtherClaims().put("enriched_roles", extractArray(body, "roles"));
        } catch (Exception e) {
            if (failClosed) throw new RuntimeException("Token enrichment failed", e);
            token.getOtherClaims().put("enrichment_status", "failed");
        }
    }
    private static String extract(String json, String key) {
        Matcher m = Pattern.compile("\\\"" + key + "\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"").matcher(json); return m.find() ? m.group(1) : null;
    }
    private static List<String> extractArray(String json, String key) {
        Matcher m = Pattern.compile("\\\"" + key + "\\\"\\s*:\\s*\\[([^]]*)]").matcher(json);
        if (!m.find()) return List.of();
        return Pattern.compile("\\\"([^\\\"]+)\\\"").matcher(m.group(1)).results().map(x -> x.group(1)).toList();
    }
}
