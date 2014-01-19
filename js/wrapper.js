Alcove.define("$$NAME$$", function($$cls) {
    $$STATIC$$

    this({
        templates  : $$TEMPLATES$$,
        css        : $$CSS$$,
        initialize : function($$widget, methods, args) {
            var $$container = $("<div class='$$CLASS$$ __widget__'></div>");
            var $$display   = function(nodes) {
                $$container.contents().detach();
                $$container.append($(nodes));
            };
            with (methods) {
                $$BODY$$
            }
            return $$container;
        }
    });

});

