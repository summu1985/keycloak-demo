package com.example.keycloak;

import jakarta.ws.rs.core.MultivaluedMap;
import jakarta.ws.rs.core.Response;
import org.keycloak.authentication.AuthenticationFlowContext;
import org.keycloak.authentication.AuthenticationFlowError;
import org.keycloak.authentication.Authenticator;
import org.keycloak.models.AuthenticatorConfigModel;
import org.keycloak.models.KeycloakSession;
import org.keycloak.models.RealmModel;
import org.keycloak.models.RoleModel;
import org.keycloak.models.UserModel;

import java.net.URI;
import java.net.URLEncoder;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**

* Username-first authenticator with just-in-time provisioning for mobile users.
*
* Existing non-mobile users are resolved normally. A 10-digit username is first
* checked against an authoritative customer registry API. Only registered and
* active customers are created locally in Keycloak. Customer attributes and
* roles are refreshed from the registry on every login.
  */
  public final class JitCustomerUsernameAuthenticator implements Authenticator {

private static final Pattern MOBILE =
        Pattern.compile("^\\d{10}$");

private static final Pattern BOOLEAN_FIELD =
        Pattern.compile("\\\"%s\\\"\\s*:\\s*(true|false)");

private static final Pattern STRING_FIELD =
        Pattern.compile("\\\"%s\\\"\\s*:\\s*\\\"([^\\\"]*)\\\"");

private static final Pattern ROLES_FIELD =
        Pattern.compile("\\\"roles\\\"\\s*:\\s*\\[(.*?)]", Pattern.DOTALL);

private static final Pattern ARRAY_STRING =
        Pattern.compile("\\\"([^\\\"]+)\\\"");

  private static final HttpClient HTTP = HttpClient.newBuilder()
  .connectTimeout(Duration.ofSeconds(2))
  .build();

  @Override
  public void authenticate(AuthenticationFlowContext context) {
  Response response = context.form()
  .setAttribute("username", "")
  .createForm("jit-username.ftl");
   context.challenge(response);
  }

  @Override
  public void action(AuthenticationFlowContext context) {
  MultivaluedMap<String, String> form =
  context.getHttpRequest().getDecodedFormParameters();

   String username = normalize(form.getFirst("username"));

   if (username == null) {
       challenge(
               context,
               "",
               "Enter your username or registered mobile number."
       );
       return;
   }

   RealmModel realm = context.getRealm();
   KeycloakSession session = context.getSession();

   if (!MOBILE.matcher(username).matches()) {
       UserModel existing =
               session.users().getUserByUsername(realm, username);

       if (existing == null || !existing.isEnabled()) {
           genericFailure(context, username);
           return;
       }

       context.setUser(existing);
       context.success();
       return;
   }

   try {
       CustomerRecord customer = lookupCustomer(context, username);

       if (!customer.registered
               || !customer.active
               || customer.customerId == null) {

           genericFailure(context, username);
           return;
       }

       UserModel user =
               session.users().getUserByUsername(realm, username);

       if (user == null) {
           user = session.users().addUser(realm, username);
           user.setEnabled(true);
       }

       user.setSingleAttribute(
               "customer_id",
               customer.customerId
       );

       user.setSingleAttribute(
               "user_type",
               customer.userType == null
                       ? "customer"
                       : customer.userType
       );

       user.setSingleAttribute(
               "mobile_number",
               username
       );

       user.setSingleAttribute(
               "registry_status",
               "ACTIVE"
       );

       for (String roleName : customer.roles) {
           RoleModel role = realm.getRole(roleName);

           if (role != null && !user.hasRole(role)) {
               user.grantRole(role);
           }
       }

       RoleModel customerRole =
               realm.getRole("customer_user");

       if (customerRole != null
               && !user.hasRole(customerRole)) {

           user.grantRole(customerRole);
       }

       context.getAuthenticationSession()
               .setUserSessionNote(
                       "derived_user_type",
                       "customer"
               );

       context.getAuthenticationSession()
               .setAuthNote(
                       "jit_customer_validated",
                       "true"
               );

       context.setUser(user);
       context.success();

   } catch (Exception e) {
       Response response = context.form()
               .setError(
                       "Customer validation service is temporarily unavailable."
               )
               .createErrorPage(
                       Response.Status.SERVICE_UNAVAILABLE
               );

       context.failureChallenge(
               AuthenticationFlowError.INTERNAL_ERROR,
               response
       );
   }
  }

  private static CustomerRecord lookupCustomer(
  AuthenticationFlowContext context,
  String mobile) throws Exception {

   String base = config(context).getOrDefault(
           "customer.registry.url",
           "http://mock-customer-registry:8080/customers/by-mobile"
   );

   URI uri = URI.create(
           base
                   + "/"
                   + URLEncoder.encode(
                           mobile,
                           StandardCharsets.UTF_8
                   )
   );

   HttpRequest request = HttpRequest.newBuilder(uri)
           .timeout(Duration.ofSeconds(3))
           .GET()
           .build();

   HttpResponse<String> response = HTTP.send(
           request,
           HttpResponse.BodyHandlers.ofString()
   );

   if (response.statusCode() / 100 != 2) {
       throw new IllegalStateException(
               "Customer registry returned "
                       + response.statusCode()
       );
   }

   String body = response.body();

   return new CustomerRecord(
           booleanField(body, "registered"),
           booleanField(body, "active"),
           stringField(body, "customerId"),
           stringField(body, "userType"),
           roles(body)
   );
  }

  private static boolean booleanField(
  String body,
  String name) {

   Matcher matcher = Pattern.compile(
           String.format(
                   BOOLEAN_FIELD.pattern(),
                   Pattern.quote(name)
           )
   ).matcher(body);

   return matcher.find()
           && Boolean.parseBoolean(matcher.group(1));

  }

  private static String stringField(
  String body,
  String name) {

   Matcher matcher = Pattern.compile(
           String.format(
                   STRING_FIELD.pattern(),
                   Pattern.quote(name)
           )
   ).matcher(body);

   return matcher.find()
           ? matcher.group(1)
           : null;

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

  private static void challenge(
  AuthenticationFlowContext context,
  String username,
  String error) {


   var form = context.form()
           .setAttribute(
                   "username",
                   username == null ? "" : username
           );

   if (error != null && !error.isBlank()) {
       form.setError(error);
   }

   context.challenge(
           form.createForm("jit-username.ftl")
   );


  }

  private static void genericFailure(
  AuthenticationFlowContext context,
  String username) {


   Response response = context.form()
           .setAttribute(
                   "username",
                   username == null ? "" : username
           )
           .setError(
                   "Unable to authenticate with the supplied identifier."
           )
           .createForm("jit-username.ftl");

   context.failureChallenge(
           AuthenticationFlowError.UNKNOWN_USER,
           response
   );


  }

  private static String normalize(String value) {
  if (value == null) {
  return null;
  }


   String normalized =
           value.trim().toLowerCase();

   return normalized.isBlank()
           ? null
           : normalized;

  }

  private static Map<String, String> config(
  AuthenticationFlowContext context) {


   AuthenticatorConfigModel model =
           context.getAuthenticatorConfig();

   return model == null
           || model.getConfig() == null
           ? Map.of()
           : model.getConfig();


  }

  private record CustomerRecord(
  boolean registered,
  boolean active,
  String customerId,
  String userType,
  List<String> roles) {
  }

  @Override
  public boolean requiresUser() {
  return false;
  }

  @Override
  public boolean configuredFor(
  KeycloakSession session,
  RealmModel realm,
  UserModel user) {


   return true;

  }

  @Override
  public void setRequiredActions(
  KeycloakSession session,
  RealmModel realm,
  UserModel user) {
  }

  @Override
  public void close() {
  }
  }
