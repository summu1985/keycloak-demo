<#import "template.ftl" as layout>

<@layout.registrationLayout
    displayMessage=true
    displayInfo=false
    displayRequiredFields=false;
    section>

    <#if section == "header">
        Sign in

    <#elseif section == "form">

        <form
            id="kc-jit-username-form"
            class="${properties.kcFormClass!}"
            action="${url.loginAction}"
            method="post">

            <div class="${properties.kcFormGroupClass!}">
                <label
                    for="username"
                    class="${properties.kcLabelClass!}">
                    Username or registered mobile number
                </label>

                <input
                    id="username"
                    name="username"
                    type="text"
                    value="${username!''}"
                    autocomplete="username"
                    autofocus
                    required
                    class="${properties.kcInputClass!}"
                />
            </div>

            <div class="${properties.kcFormGroupClass!}">
                <input
                    id="kc-login"
                    name="login"
                    type="submit"
                    value="Continue"
                    class="${properties.kcButtonClass!}
                           ${properties.kcButtonPrimaryClass!}
                           ${properties.kcButtonBlockClass!}
                           ${properties.kcButtonLargeClass!}"
                />
            </div>
        </form>

    </#if>

</@layout.registrationLayout>
