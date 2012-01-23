(function() {
  this.WEB_SOCKET_SWF_LOCATION = '/socket.io/WebSocketMain.swf';
  $(function() {
    var join, logRows, msgRow, onHash;
    msgRow = function(_arg) {
      var date, h, m, message, sender, time, timestamp, tr;
      timestamp = _arg.timestamp, sender = _arg.sender, message = _arg.message;
      date = new Date(timestamp);
      h = date.getHours();
      if (h < 10) {
        h = '0' + h;
      }
      m = date.getMinutes();
      if (m < 10) {
        m = '0' + m;
      }
      time = [h, m].join(':');
      tr = $('<tr class="line">');
      $('<td class="timestamp">').text(time).attr('title', date.toString()).appendTo(tr);
      $('<td class="nick">').text("<" + sender + ">").appendTo(tr);
      $('<td class="message">').text(message || ' ').appendTo(tr);
      return tr.get(0);
    };
    logRows = function(log) {
      var line, lines, message, result, sender, timestamp, _i, _len, _ref;
      result = [];
      lines = log.split(/\n/);
      lines.pop();
      for (_i = 0, _len = lines.length; _i < _len; _i++) {
        line = lines[_i];
        _ref = line.split(/\t/, 3), timestamp = _ref[0], sender = _ref[1], message = _ref[2];
        timestamp = parseInt(timestamp);
        result.push({
          timestamp: timestamp,
          sender: sender,
          message: message
        });
      }
      return result;
    };
    join = function(url) {
      var el, more;
      el = $('<table class="log">\n    <tr class="more">\n        <td colspan="3">More...</td>\n    </tr>\n</table>');
      el.prepend("<caption>" + url);
      more = el.find('.more');
      return $.getJSON(url, function(channel) {
        var socket;
        el.appendTo('body');
        $.get(channel.current, function(log) {
          var r;
          return el.append((function() {
            var _i, _len, _ref, _results;
            _ref = logRows(log);
            _results = [];
            for (_i = 0, _len = _ref.length; _i < _len; _i++) {
              r = _ref[_i];
              _results.push(msgRow(r));
            }
            return _results;
          })());
        });
        socket = io.connect(channel.socket);
        console.log(channel.socket);
        socket.on('chat', function(data) {
          console.log("something");
          return el.append(msgRow(data));
        });
        return $.get(channel.archive, function(unparsed) {
          var archives, get, updateMore;
          archives = unparsed.split(/\n/);
          archives.pop();
          get = function() {
            more.unbind('click');
            return $.get(archives.pop(), function(log) {
              var r;
              more.after((function() {
                var _i, _len, _ref, _results;
                _ref = logRows(log);
                _results = [];
                for (_i = 0, _len = _ref.length; _i < _len; _i++) {
                  r = _ref[_i];
                  _results.push(msgRow(r));
                }
                return _results;
              })());
              return updateMore();
            });
          };
          updateMore = function() {
            if (archives.length > 0) {
              return more.click(get);
            } else {
              return more.remove();
            }
          };
          return updateMore();
        });
      });
    };
    onHash = function() {
      var u, urls, _i, _len, _ref, _results;
      $('.log').remove();
      urls = location.hash.replace(/^#/, '');
      _ref = urls.split(/,/);
      _results = [];
      for (_i = 0, _len = _ref.length; _i < _len; _i++) {
        u = _ref[_i];
        _results.push(join(u));
      }
      return _results;
    };
    $(window).on('hashchange', onHash);
    return onHash();
  });
}).call(this);
