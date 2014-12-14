dojo.addOnLoad(function() {
    dojo.require("dojo.parser");
    dojo.require("dijit.form.Form");
    dojo.require("dijit.form.ValidationTextBox");
    dojo.require("vhffs.Common");

    dojo.requireLocalization("vhffs", "prompt");
    var prompts = dojo.i18n.getLocalization("vhffs", "prompt");
    var infoImg = '<img src="/themes/' + vhffs.Common.theme + '/img/info.png" alt="info"/> ';

    dojo.parser.instantiate( dojo.query("input.validation-identifier"), {
        dojoType: "dijit.form.ValidationTextBox",
        required: true,
        regExp: "^[a-z0-9]{3,12}$",
        promptMessage: infoImg + prompts.identifier
    });

    dojo.parser.instantiate( dojo.query("input.validation-email"), {
        dojoType: "dijit.form.ValidationTextBox",
        required: true,
        regExp: "^[_a-z0-9-]+(\\.[_a-z0-9-]+)*@[a-z0-9-]+(\\.[a-z0-9-]+)*(\\.[a-z]{2,10})$",
        promptMessage: infoImg + prompts.email
    });

    dojo.parser.instantiate( dojo.query("input.validation-string"), {
        dojoType: "dijit.form.ValidationTextBox",
        required: true,
        regExp: "^[^<>\"]+$",
        promptMessage: infoImg + prompts.string
    });

    dojo.parser.instantiate( dojo.query("input.validation-zipcode"), {
        dojoType: "dijit.form.ValidationTextBox",
        required: true,
        regExp: "^[\\w\\d\\s\\-]+$",
        promptMessage: infoImg + prompts.zipcode
    });

    dojo.parser.instantiate( [ dojo.byId("subscribe-form") ], {
        dojoType: "dijit.form.Form",
        onSubmit: function(e) {
            if(this.validate() == false) {
                dojo.stopEvent(e);
            }
        }
    });
});
