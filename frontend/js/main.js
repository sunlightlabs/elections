(function($) {

// Models
var District = Backbone.Model.extend({ url: function() { return "/json/districts/" + this.id; } });

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
var DistrictView;

// Router
var AppRouter = Backbone.Router.extend({
    initialize: function() {
        //routes
        this.route("district/:id", "districtDetail");
        this.route("", "home");
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