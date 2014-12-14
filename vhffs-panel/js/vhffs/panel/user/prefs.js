dojo.addOnLoad(function() {
    dojo.require("dojo.fx");
    dojo.require("dojo.parser");

    var mailUsage = dojo.byId("platform-email-options");
    var mailUsageWipeIn = dojo.fx.wipeIn( { node: mailUsage } );
    var mailUsageWipeOut = dojo.fx.wipeOut( { node: mailUsage } );
    dojo.connect(dojo.byId("activate-platform-email"), "onchange", function() {
        if(this.checked) {
            mailUsageWipeOut.stop();
            mailUsageWipeIn.play();
        } else {
            mailUsageWipeIn.stop();
            mailUsageWipeOut.play();
        }
    });

    var mailboxOptions = dojo.byId("platform-email-box-options");
    var mailBoxOptionsWipeIn = dojo.fx.wipeIn( { node: mailboxOptions });
    var mailBoxOptionsWipeOut = dojo.fx.wipeOut( { node: mailboxOptions });
    dojo.connect(dojo.byId("plaftorm-email-option-box"), "onchange", handleMailBoxOptionChange);
    dojo.connect(dojo.byId("plaftorm-email-option-forward"), "onchange", handleMailBoxOptionChange);


    function handleMailBoxOptionChange() {
        if(dojo.byId("plaftorm-email-option-box").checked) {
            mailBoxOptionsWipeOut.stop();
            mailBoxOptionsWipeIn.play();
        } else {
            mailBoxOptionsWipeIn.stop();
            mailBoxOptionsWipeOut.play();
        }
    }
});
