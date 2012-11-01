// Avoid `console` errors in browsers that lack a console.
(function() {
    var method;
    var noop = function noop() {};
    var methods = [
        'assert', 'clear', 'count', 'debug', 'dir', 'dirxml', 'error',
        'exception', 'group', 'groupCollapsed', 'groupEnd', 'info', 'log',
        'markTimeline', 'profile', 'profileEnd', 'table', 'time', 'timeEnd',
        'timeStamp', 'trace', 'warn'
    ];
    var length = methods.length;
    var console = (window.console = window.console || {});

    while (length--) {
        method = methods[length];

        // Only stub undefined methods.
        if (!console[method]) {
            console[method] = noop;
        }
    }
}());

// Place any jQuery/helper plugins in here.
$(document).ready(function() {

    $('#sfapp-subscribe-form').submit(function(ev) {

        var $form = $(this);

        var csrfToken = $form.find('input[name=csrfmiddlewaretoken]').val();
        var email = $form.find('input[name=email]').val();
        var zipcode = $form.find('input[name=zipcode]').val();

        var params = {
                csrfmiddlewaretoken: csrfToken,
                email: email,
                zipcode: zipcode
        };

        $.post('/subscribe/', params, function(resp) {
                var $p = $('<p>').text(resp.message).hide();
                $form.slideUp('fast', function() {
                        $form.after($p);
                        $p.slideDown();
                });
        });

        ev.preventDefault();

    });

});