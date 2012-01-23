@WEB_SOCKET_SWF_LOCATION = '/socket.io/WebSocketMain.swf'
$ ->
    msgRow = ({timestamp, sender, message}) ->
        date  = new Date(timestamp)
        h     = date.getHours()
        h     = '0' + h if h < 10
        m     = date.getMinutes()
        m     = '0' + m if m < 10
        time  = [h, m].join ':'

        tr = $ '<tr class="line">'
        $('<td class="timestamp">')
            .text(time)
            .attr('title', date.toString())
            .appendTo(tr)
        $('<td class="nick">').text("<#{sender}>").appendTo(tr)
        $('<td class="message">').text(message or ' ').appendTo(tr)
        return tr.get 0

    logRows = (log) ->
        result = []
        lines = log.split /\n/
        lines.pop() # newline at end-of-file

        for line in lines
            [timestamp, sender, message] = line.split /\t/, 3
            timestamp = parseInt(timestamp)
            result.push({timestamp, sender, message})
        return result

    join = (url) ->
        el = $ '''
            <table class="log">
                <tr class="more">
                    <td colspan="3">More...</td>
                </tr>
            </table>
            '''
        el.prepend "<caption>#{url}"
        more = el.find '.more'
        $.getJSON url, (channel) ->
            el.appendTo('body')
            $.get channel.current, (log) ->
                el.append (msgRow r for r in logRows log)

            socket = io.connect(channel.socket)
            console.log(channel.socket)
            socket.on 'chat', (data) ->
                console.log "something"
                el.append(msgRow data)

            $.get channel.archive, (unparsed) ->
                archives = unparsed.split /\n/
                archives.pop() # newline at end-of-file

                get = ->
                    more.unbind 'click'
                    $.get archives.pop(), (log) ->
                        more.after (msgRow r for r in logRows log)
                        updateMore()

                updateMore = ->
                    if archives.length > 0
                        more.click get
                    else
                        more.remove()

                updateMore()

    onHash = ->
        $('.log').remove()
        urls = location.hash.replace /^#/, ''
        join u for u in urls.split /,/

    $(window).on 'hashchange', onHash
    onHash()
