package com.example.keycloak;

import org.keycloak.models.ClientSessionContext;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.ProtocolMapperModel;
import org.keycloak.models.RoleModel;
import org.keycloak.models.UserSessionModel;
import org.keycloak.protocol.oidc.mappers.AbstractOIDCProtocolMapper;
import org.keycloak.protocol.oidc.mappers.OIDCAccessTokenMapper;
import org.keycloak.provider.ProviderConfigProperty;
import org.keycloak.representations.IDToken;

import java.util.List;
import java.util.stream.Collectors;

public final class CommaSeparatedRolesProtocolMapper extends AbstractOIDCProtocolMapper implements OIDCAccessTokenMapper {
    public static final String PROVIDER_ID = "comma-separated-roles-mapper";
    @Override public String getDisplayCategory() { return "Token mapper"; }
    @Override public String getDisplayType() { return "Comma-separated realm roles"; }
    @Override public String getHelpText() { return "Adds effective realm roles as a comma-separated claim named roles_csv."; }
    @Override public List<ProviderConfigProperty> getConfigProperties() { return List.of(); }
    @Override public String getId() { return PROVIDER_ID; }
    @Override protected void setClaim(IDToken token, ProtocolMapperModel mappingModel, UserSessionModel userSession, KeycloakSession session, ClientSessionContext clientSessionCtx) {
        String csv = userSession.getUser().getRoleMappingsStream().map(RoleModel::getName).sorted().collect(Collectors.joining(","));
        token.getOtherClaims().put("roles_csv", csv);
    }
}
