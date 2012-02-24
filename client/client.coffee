@WEB_SOCKET_SWF_LOCATION = '/socket.io/WebSocketMain.swf'

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
    lines = log.split /\n/
    lines.pop() # newline at end-of-file

    for line in lines
        [timestamp, sender, message] = line.split /\t/, 3
        timestamp = parseInt(timestamp)
        {timestamp, sender, message}

channels = {}

leave = (chan) ->
    tab = channels[chan]
    delete channels[chan]
    tab.button.remove()
    tab.content.remove()
    if tab.active
        for k of channels
            select k
            break

join = (url) ->
    el = $ '''
        <div class='tab'>
            <div class='more'>More...</div>
            <table class="log">
                <caption></caption>
            </table>
        </div>
        '''

    tab   = {}
    more  = el.find '.more'
    tbl   = el.find '.log'
    tbl.find('caption').text(url)

    $.getJSON url, (channel) ->
        $.get channel.current, (log) ->
            tbl.append (msgRow r for r in logRows log)
            scroll()

        if socketInfo = channel.socket
            socket = io.connect socketInfo.server
            rjoin  = -> socket.emit 'join', socketInfo.room
            rjoin()
            socket.on 'reconnect', rjoin

            socket.on 'chat', (data) ->
                return unless data.channel is channel
                el = $('#tab-content')
                auto = (el.height() + el.scrollTop()) is el.prop('scrollHeight')
                tbl.append(msgRow data)
                scroll() if auto

        $.getJSON channel.archive, (urls) ->
            archives = (parseInt(k) for k of urls)
            archives.sort()

            get = ->
                more.unbind 'click'
                $.get urls[archives.pop()], (log) ->
                    tbl.prepend (msgRow r for r in logRows log).reverse()
                    updateMore()

            updateMore = ->
                if archives.length > 0
                    more.click get
                else
                    more.remove()

            updateMore()
            el.appendTo('#tab-content')
            tab.content = el
            tab.button = $('<li class="tab-title">')
                .text(channel.channel)
                .prepend(
                    $('<span class="close"> x </span>').click (e) ->
                        now = (k for k of channels when k isnt url)
                        location.hash = now.join ','
                        e.stopPropagation()
                ).click(-> select url)
                .prependTo('#tab-buttons')
            channels[url] = tab
            select url
            expand()

select = (channel) ->
    for chan, tab of channels
        tab.content.removeClass 'active'
        tab.button.removeClass 'active'
        tab.active = false

    tab = channels[channel]
    tab.active = true
    tab.content.addClass 'active'
    tab.button.addClass 'active'
    scroll()

onHash = ->
    urls = location.hash.replace /^#/, ''
    set = {}
    set[u] = true for u in urls.split /,/ when u

    for chan, tab of channels
        unless chan of set
            leave chan

    for chan of set
        unless chan of channels
            join chan

expand = ->
    el = $('#tab-content')
    el.height $(window).height() - el.position().top

scroll = ->
    el = $('#tab-content')
    el.animate {scrollTop: el.prop('scrollHeight')}, 'fast'

$ ->
    $('#join').click ->
        url = prompt 'Channel url:'
        return if channels[url]
        if location.hash
            location.hash += ',' + url
        else
            location.hash = url

    $(window).on 'hashchange', onHash
    $(window).on 'resize', expand
    onHash()
