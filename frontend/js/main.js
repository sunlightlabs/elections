(function($) {

// Models
var District = Backbone.Model.extend({ url: function() { return "/json/" + this.id + ".json"; } });

// Template Helpers
var helpers = {
    colorOf: function(endorsement) {
        if (endorsement.type === "grade") {
            var letter = endorsement.value.charAt(0);
            if (letter <= "B") {
                return "green";
            } else if (letter <= "C") {
                return "yellow";
            } else {
                return "red";
            }
        } else if (endorsement.type == "endorsement") {
            return endorsement.value == "Y" ? "green" : "red";
        } else if (endorsement.type == "rating") {
            var rating = parseInt(endorsement.value);
            if (rating >= 75) {
                return "green";
            } else if (rating >= 50) {
                return "yellow";
            } else {
                return "red";
            }
        }
    },
    formatDollars: function(number) {
        number = parseFloat(number);
        var out = [], counter = 0, part = true;
        var digits = number.toFixed(0).split("");
        while (part) {
            part = (counter == 0 ? digits.slice(-3) : digits.slice(counter - 3, counter)).join("");
            if (part) {
                out.unshift(part);
                counter -= 3;
            }
        }
        return out.join(",");
    },
    ordinal: function(n) {
        var i = parseInt(n, 10);
        if (isNaN(i)) return n.replace("_", " ");
        var s=["th","st","nd","rd"],
            v=i%100;
        return i+(s[(v-20)%10]||s[v]||s[0]);
    }
}

var errors = {
    'address_error': {
        'title': 'Address Error',
        'message': "The address you've entered can't be found."
    },
    'not_in_district': {
        'title': 'Address Error',
        'message': "The address you've entered is not in a congressional district."
    },
    'district_not_found': {
        'title': 'District not found',
        'message': "You've entered a district that can't be found."
    }
}

// Views
var HomeView = Backbone.View.extend({
    tagName: 'div',
    id: 'home-view',

    template: _.template($('#home-tpl').html()),
    render: function() {
        this.$el.html(this.template({}));
        return this;
    }
});

var DistrictView = Backbone.View.extend({
    tagName: 'div',
    id: 'district-view',

    template: _.template($('#district-tpl').html()),
    candidateTemplate: _.template($('#candidate-tpl').html()),
    render: function() {
        this.model.fetch({
            'success': $.proxy(function() {
                var view = this;
                var context = this.model.toJSON();
                this.$el.html(this.template(_.extend(context, helpers, {'candidateTemplate': function(ctx) { return view.candidateTemplate(_.extend({}, helpers, ctx)); } })));
            }, this),
            'error': function() {
                app.navigate("error/district_not_found", {'trigger': true});
            }
        })
        return this;
    }
});

var SearchView = Backbone.View.extend({
    events: {
        'submit form': 'search'
    },

    search: function(evt) {
        var form = this.$el.find('.form-search');
        var address = form.find('input[type=text]').val();
        if (!address) return false;

        form.addClass('loading');

        var geocoder = new google.maps.Geocoder();

        if (geocoder) {
            geocoder.geocode({'address': address}, function (results, status) {
                if (status == google.maps.GeocoderStatus.OK) {
                    var loc = results[0].geometry.location;
                    $.getJSON("http://pentagon.sunlightlabs.net/1.0/boundary/?shape_type=none&sets=cd2012&callback=?&contains=" + loc.Ya + "," + loc.Za, function(response) {
                        form.removeClass('loading');
                        if (response.objects.length == 0) {
                            app.navigate("error/not_in_district", {'trigger': true});
                        } else {
                            var parts = response.objects[0].name.split(" ");
                            var state = parts[0];

                            var p1 = parseInt(parts[1]);
                            var district = p1 > 60 || p1 < 1 ? "at_large" : parts[1];
                            app.navigate("district/" + state + "-" + district, {'trigger': true});
                        }
                    });
                } else {
                    form.removeClass('loading');
                    app.navigate("error/address_error", {'trigger': true});
                }
            });
        }
        evt.preventDefault();
        return false;
    }
});

var ErrorView = Backbone.View.extend({
    template: _.template($('#error-tpl').html()),
    render: function() {
        this.$el.html(this.template({'error': this.model}));
        return this;
    }
})

// Router
var AppRouter = Backbone.Router.extend({
    initialize: function() {
        //routes
        this.route("district/:id", "districtDetail");
        this.route("error/:id", "error");
        this.route("", "home");

        var searchView = new SearchView({'el': $('#main-header').get(0)});
    },

    home: function() {
        var homeView = new HomeView({});
        $('#main').html(homeView.render().el);
    },

    districtDetail: function(id) {
        var district = new District({'id': id});
        var view = new DistrictView({model: district});
        $('#main').html(view.render().el);
    },

    error: function(id) {
        var error = errors[id];
        var view = new ErrorView({'model': error});
        $("#main").html(view.render().el);
    }
});

var app = new AppRouter();
window.app = app;

Backbone.history.start();

/* assume backbone link handling, from Tim Branyen */
$(document).on("click", "a:not([data-bypass])", function(evt) {
    if (evt.isDefaultPrevented() || evt.metaKey || evt.ctrlKey) {
        return;
    }

    var href = $(this).attr("href");
    var protocol = this.protocol + "//";

    if (href && href.slice(0, protocol.length) !== protocol &&
        href.indexOf("javascript:") !== 0) {
        evt.preventDefault();
        Backbone.history.navigate(href, true);
    }
});

})(jQuery);