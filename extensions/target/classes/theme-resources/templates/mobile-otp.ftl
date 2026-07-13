<#import "template.ftl" as layout>
<@layout.registrationLayout displayMessage=!messagesPerField.existsError('otp'); section>
  <#if section = "header">
    Verify mobile number
  <#elseif section = "form">
    <form id="kc-mobile-otp-form" action="${url.loginAction}" method="post">
      <div class="pf-v5-c-form__group">
        <label for="otp" class="pf-v5-c-form__label">
          Enter the OTP sent to ${mobile!username!''}
        </label>
        <input id="otp" name="otp" type="text" inputmode="numeric"
               pattern="[0-9]*" maxlength="8" autocomplete="one-time-code"
               autofocus class="pf-v5-c-form-control" />
      </div>
      <div class="pf-v5-c-form__group pf-m-action">
        <input class="pf-v5-c-button pf-m-primary pf-m-block"
               name="login" type="submit" value="Verify OTP" />
      </div>
    </form>
  </#if>
</@layout.registrationLayout>
