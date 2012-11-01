(function($) {

// Models
var District = Backbone.Model.extend({ url: function() { return "/json/" + this.id + ".json"; } });

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
        console.log('test');
        this.model.fetch({
            'success': $.proxy(function() {
                var context = this.model.toJSON();
                this.$el.html(this.template({'candidates': context, 'candidateTemplate': this.candidateTemplate}));
            }, this),
            'error': function() {
                console.log('failed');
            }
        })
        return this;
    }
});

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
        console.log('arg');
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