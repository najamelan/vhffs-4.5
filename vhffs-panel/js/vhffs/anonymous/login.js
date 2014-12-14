dojo.addOnLoad(function() {
    dojo.require("dojo.parser");
    dojo.require("dijit.form.Form");
    dojo.require("dijit.form.ValidationTextBox");

    dojo.parser.instantiate( dojo.query("input.validation-identifier"), {
        dojoType: "dijit.form.ValidationTextBox",
        required: true,
        regExp: "^[a-z0-9]{3,12}$"
    });

    dojo.parser.instantiate( dojo.query("input.validation-required"), {
        dojoType: "dijit.form.ValidationTextBox",
        required: true
    });

    dojo.attr(dijit.byId("login-username").textbox, "autocomplete", "on");
    dojo.attr(dijit.byId("login-password").textbox, "autocomplete", "on");

    dojo.parser.instantiate( [ dojo.byId("login-form") ], {
        dojoType: "dijit.form.Form",
        onSubmit: function(e) {
            if(this.validate() == false) {
                dojo.stopEvent(e);
            }
        }
    });
});
