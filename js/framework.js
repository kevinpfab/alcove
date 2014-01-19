
// {{{ $() augmentation
(function() {
    var old_init = jQuery.fn.init;
    jQuery.fn.init = function() {
        var final_arguments = [];
        $.each(arguments, function(idx, elem) {
            var arg = elem;
            if (elem && elem.__root) {
                arg = elem.__root;
            }
            final_arguments.push(arg);
        });
        function F() {
            return old_init.apply(this, final_arguments);
        }
        F.prototype = old_init.prototype;
        return new F();
    };
}());
// }}}

Alcove = (function() {
    var self = {};
    self.Widget = {};
    self.Widget.prototype = {};

    // {{{ _id_gen
    var _id = 0;
    function _id_gen() {
        return "" + (++_id);
    }

    // }}}

    // Handlebars helpers
    // {{{ widget
    var _widgets = {};
    function _widget(class_name/*, [params] */) {
        var params = Array.prototype.slice.call(arguments, 1);
        var id = _id_gen();
        var cls = window;
        $.each(class_name.split('.'), function(idx, part) {
            if (cls) {
                cls = cls[part];
            }
        });
        if (!cls) {
            throw "Invalid widget class " + class_name;
        }
        _widgets[id] = (function() {
            function F(args) {
                return cls.apply(this, args);
            }
            F.prototype = cls.prototype;
            $.extend(F, cls);
            return new F(params);
        })();
        var contents = "<div class='widget_placeholder' data-id='" + id + "'></div>";
        return new Handlebars.SafeString(contents);
    }
    Handlebars.registerHelper('widget', _widget);

    // }}}
    // {{{ node
    var _nodes = {};
    function _node(value) {
        var id = _id_gen();
        if ($(value).filter("*").length === 0) {
            value = $("<span>" + value + "</span>");
        }
        _nodes[id] = value;
        var contents = "<div class='node_placeholder' data-id='" + id + "'></div>";
        return new Handlebars.SafeString(contents);
    }
    Handlebars.registerHelper('node', _node);

    // }}}
    // {{{ template
    var _templates = {};
    function _template(name/*[, context], options*/) {
        var args = {};
        var params = Array.prototype.slice.call(arguments, 1);
        if (params.length == 1) {
            // Context not provided
            args = params[0].hash;
        } else {
            // Context provided
            args = $.extend({}, (params[1].hash || {}), params[0]);
        }

        var id = _id_gen();
        _templates[id] = {
            name : name,
            args : args
        };
        var contents = "<div class='template_placeholder' data-id='" + id + "'></div>";
        return new Handlebars.SafeString(contents);
    }
    Handlebars.registerHelper('template', _template);

    // }}}
    // {{{ text
    function text(key) {
        return new Handlebars.SafeString(
            self.text.apply(null, Array.prototype.slice.call(arguments, 0, -1))
        );
    }
    Handlebars.registerHelper("text", text);

    // }}}
    // {{{ render
    function render(text) {
        return new Handlebars.SafeString(
            text.replace(/\n/g, "<br/>")
                .replace(/\*(.*?)\*/g, function(match, str) {
                    return "<b>" + str + "</b>";
                })
        );
    }
    Handlebars.registerHelper('render', render);

    // }}}
    // {{{ render_text
    function render_text() {
        return render(self.text.apply(null, arguments));
    }
    Handlebars.registerHelper('render_text', render_text);

    // }}}

    // Private
    // {{{ _apply_css
    function _apply_css(css) {
        if (css) {
            if ($('#widget_styles').length === 0) {
                $('head')[0].appendChild($("<style id='widget_styles' type='text/css'></style>")[0]);
            }
            var style = $('#widget_styles')[0];

            var rules = document.createTextNode(css);
            if(style.styleSheet) { // IE
                style.styleSheet.cssText = style.styleSheet.cssText + rules.nodeValue;
            } else {
                style.appendChild(rules);
            }
        }
    }

    // }}}
    // {{{ _methods
    function _methods(cls, info) {
        var get_template = function(name, data) {
            var input = data;
            if (!input) {
                input = {};
            }

            var tmpl = info.templates[name];
            if (typeof(tmpl) == 'undefined') {
                tmpl = function() {
                    return '<div></div>';
                };
            }

            return tmpl(input);
        };

        var methods = {
            $$template: function(name, data) {
                function render(context) {
                    var rendered = $('<div>' + get_template(name, context) + '</div>');
                    $('div.node_placeholder', rendered).replaceWith(function() {
                        var id  = $(this).attr('data-id');
                        var node = _nodes[id];
                        delete _nodes[id];
                        return node;
                    });
                    $('div.widget_placeholder', rendered).replaceWith(function() {
                        var id  = $(this).attr('data-id');
                        var wid = _widgets[id];
                        return wid.__root;
                    });
                    $('div.template_placeholder', rendered).replaceWith(function() {
                        var id  = $(this).attr('data-id');
                        var tmpl_data = _templates[id];
                        delete _templates[id];
                        var inner = methods.$$template(tmpl_data.name, tmpl_data.args);
                        return inner;
                    });

                    return rendered.contents();
                }

                var current_render = render(data);
                current_render.context = data;

                current_render.rerender = function() {
                    var new_render = render(current_render.context);
                    for (var i = 0; i < current_render.length; i++) {
                        $(current_render[i]).replaceWith($(new_render[i]));
                    }

                    // Keep current node but replace contents so others can keep references alive
                    var args = new_render.toArray();
                    args.unshift(0, current_render.length);
                    current_render.splice.apply(current_render, args);
                };
                return current_render;
            },
            $$text: function(key) {
                return self.text(key);
            }
        };

        return methods;
    }

    // }}}

    // Public
    // {{{ define
    self.define = function(name, setup) {
        var parts = name.split('.');
        var current = window;
        var x;
        for (x = 0; x < parts.length - 1; x++) {
            if (!current[parts[x]]) {
                current[parts[x]] = {};
            }
            current = current[parts[x]];
        }
        var last = parts[parts.length-1];
        if (current[last]) {
            throw "Object must not already exist for a widget to be defined: " + name;
        }
        var info;
        var impl = function() {};
        var cls = current[last] = function() {
            return impl.apply(this, arguments);
        };
        $.extend(cls.prototype, Alcove.Widget.prototype);

        // Initializes static data/methods
        setup.call(function(p) {
            info = p;
            _apply_css(info.css);
        }, cls);

        var methods;
        impl = function() {
            var root = info.initialize.call(current[last], this, methods, arguments);
            this.__root = root;
            var id = _id_gen();
            $(root)[0].__widget_id = id;
            _widgets[id] = this;
        };
        methods = _methods(cls, info);        
    };

    // }}}
    // {{{ from_node
    self.from_node = function(node) {
        return _widgets[$(node)[0].__widget_id];

    };

    // }}}
    // {{{ text
    self.text = function(key) {
        var params = Array.prototype.slice.call(arguments, 1);

        var str = Alcove.TEXT[key];
        if (!str) {
            if (console) {
                console.log("Undefined text key: " + key);
            }
            str = '';
        }

        for (var i = 0; i < params.length; i++) {
            str = str.replace(new RegExp("\\$" + (i+1), 'g'), params[i]);
        }

        return str;
    };

    // }}}

    return self;
}());
