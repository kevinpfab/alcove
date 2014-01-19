return function(message_key) {
    /**
     * Available $$variables:
     *
     * $$container - a jquery set containing a single div that will contain everything in $$main.
     *               Events should be bound to this element, using event delegation, when possible.
     * $$display   - a method to set the main of the $$container.  This *must* be called
     * $$template  - a method for instantiating templates - takes a template name ('main' for
     *               'main.html', and a handlebars context.  The handlebars context will be
     *               permantly bound to the result of this call, allowing you to change values later
     *               and call 'rerender' on the result of this function anytime you like.
     *               Returns a jquery set.
     * $$widget    - "this"
     */

    var main = $$template('main', {
        msg: $$text(message_key)
    });
    $$display(main);

    // Private
    function _populate(msg) {
        main.context.msg = msg;
        main.rerender();
    }

    // Events
    $$container.on('click', 'a', function() {
        _populate(prompt('Enter new message'));
    });

    // Public
    $$widget.populate = _populate;
};
