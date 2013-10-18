WebRtcJingle = ->
  unless window.webkitRTCPeerConnection
    msg = "webkitRTCPeerConnection not supported by this browser"
    alert msg
    throw Error(msg)
  @remoteOffer = null
  @localStream = null
  @callback = null
  @pc = null
  @sid = null
  @farParty = null
  @interval = null
  @inviter = false
  @peerConfig = null
  @jid = null
  @candidates = new Array()

WebRtcJingle::startApp = (callback, peerConfig) ->
  console.log "startApp"
  @callback = callback
  @peerConfig = peerConfig
  @getUserMedia()

WebRtcJingle::startScreenShare = (callback, peerConfig) ->
  console.log "startScreenShare"
  @callback = callback
  @peerConfig = peerConfig
  @getScreenMedia()

WebRtcJingle::stopApp = ->
  console.log "stopApp"
  @jingleTerminate()
  @pc.close()  if @pc?
  @pc = null

WebRtcJingle::getUserMedia = ->
  console.log "getUserMedia"
  navigator.webkitGetUserMedia
    audio: true
    video: true
  , @onUserMediaSuccess.bind(this), @onUserMediaError.bind(this)

WebRtcJingle::getScreenMedia = ->
  console.log "getScreenMedia"
  navigator.webkitGetUserMedia
    video:
      mandatory:
        chromeMediaSource: "screen"
  , @onUserMediaSuccess.bind(this), @onUserMediaError.bind(this)

WebRtcJingle::onUserMediaSuccess = (stream) ->
  url = webkitURL.createObjectURL(stream)
  console.log "onUserMediaSuccess " + url
  @localStream = stream
  @callback.startLocalMedia url  if @callback?

WebRtcJingle::onUserMediaError = (error) ->
  console.log "onUserMediaError " + error.code

WebRtcJingle::onMessage = (packet) ->
  console.log "webrtc - onMessage"
  console.log packet
  elem = @textToXML(packet)
  if elem.nodeName is "iq"
    if elem.getAttribute("type") is "result"
      channels = elem.getElementsByTagName("channel")
      if channels.length > 0
        relayHost = channels[0].getAttribute("host")
        relayLocalPort = channels[0].getAttribute("localport")
        relayRemotePort = channels[0].getAttribute("remoteport")
        console.log "add JingleNodes candidate: " + relayHost + " " + relayLocalPort + " " + relayRemotePort
        @sendTransportInfo "0", "a=candidate:3707591233 1 udp 2113937151 " + relayHost + " " + relayRemotePort + " typ host generation 0"
        candidate = new RTCIceCandidate(
          sdpMLineIndex: "0"
          candidate: "a=candidate:3707591233 1 udp 2113937151 " + relayHost + " " + relayLocalPort + " typ host generation 0"
        )
        @pc.addIceCandidate candidate
    else unless elem.getAttribute("type") is "error"
      jingle = elem.firstChild
      @sid = jingle.getAttribute("sid")
      if jingle.nodeName is "jingle" and jingle.getAttribute("action") isnt "session-terminate"
        @createPeerConnection()  unless @pc?
        if jingle.getAttribute("action") is "transport-info"
          if jingle.getElementsByTagName("candidate").length > 0
            candidate = jingle.getElementsByTagName("candidate")[0]
            ice =
              sdpMLineIndex: candidate.getAttribute("label")
              candidate: candidate.getAttribute("candidate")

            iceCandidate = new RTCIceCandidate(ice)
            unless @farParty?
              @candidates.push iceCandidate
            else
              @pc.addIceCandidate iceCandidate
        else
          if jingle.getElementsByTagName("webrtc").length > 0
            sdp = jingle.getElementsByTagName("webrtc")[0].firstChild.data
            if jingle.getAttribute("action") is "session-initiate"
              @inviter = false
              @remoteOffer = new RTCSessionDescription(
                type: "offer"
                sdp: sdp
              )
              @callback.incomingCall elem.getAttribute("from")  if @callback?
            else
              @inviter = true
              @pc.setRemoteDescription new RTCSessionDescription(
                type: "answer"
                sdp: sdp
              )
              @addJingleNodesCandidates()
      else
        @doCallClose()

WebRtcJingle::acceptCall = (farParty) ->
  console.log "acceptCall"
  @farParty = farParty
  @pc.setRemoteDescription @remoteOffer

WebRtcJingle::onConnectionClose = ->
  console.log "webrtc - onConnectionClose"
  @doCallClose()

WebRtcJingle::jingleInitiate = (farParty) ->
  console.log "jingleInitiate " + farParty
  @farParty = farParty
  @inviter = true
  @sid = "webrtc-initiate-" + Math.random().toString(36).substr(2, 9)
  @createPeerConnection()
  if @pc?
    webrtc = this
    @pc.createOffer (desc) ->
      webrtc.pc.setLocalDescription desc
      webrtc.sendJingleIQ desc.sdp


WebRtcJingle::jingleTerminate = ->
  console.log "jingleTerminate"
  @sendJingleTerminateIQ()
  @doCallClose()

WebRtcJingle::doCallClose = ->
  @pc.close()  if @pc?
  @pc = null
  @farParty = null
  @callback.terminatedCall()  if @callback?

WebRtcJingle::createPeerConnection = ->
  console.log "createPeerConnection"
  @pc = new window.webkitRTCPeerConnection(@peerConfig)
  @pc.onicecandidate = @onIceCandidate.bind(this)
  @pc.onstatechange = @onStateChanged.bind(this)
  @pc.onopen = @onSessionOpened.bind(this)
  @pc.onaddstream = @onRemoteStreamAdded.bind(this)
  @pc.onremovestream = @onRemoteStreamRemoved.bind(this)
  @pc.addStream @localStream
  @candidates = new Array()

WebRtcJingle::onIceCandidate = (event) ->
  console.log "onIceCandidate"
  while @candidates.length > 0
    candidate = @candidates.pop()
    console.log "Retrieving candidate " + candidate.candidate
    @pc.addIceCandidate candidate
  @sendTransportInfo event.candidate.sdpMLineIndex, event.candidate.candidate  if event.candidate and @callback?

WebRtcJingle::sendTransportInfo = (sdpMLineIndex, candidate) ->
  console.log "sendTransportInfo"
  id = "webrtc-jingle-" + Math.random().toString(36).substr(2, 9)
  jingleIq = "<iq type='set' to='" + @farParty + "' id='" + id + "'>"
  jingleIq = jingleIq + "<jingle xmlns='urn:xmpp:jingle:1' action='transport-info' initiator='" + @jid + "' sid='" + @sid + "'>"
  jingleIq = jingleIq + "<transport xmlns='http://phono.com/webrtc/transport'><candidate label='" + sdpMLineIndex + "' candidate='" + candidate + "' /></transport></jingle></iq>"
  @callback.sendPacket jingleIq

WebRtcJingle::onSessionOpened = (event) ->
  console.log "onSessionOpened"
  console.log event

WebRtcJingle::onRemoteStreamAdded = (event) ->
  url = webkitURL.createObjectURL(event.stream)
  console.log "onRemoteStreamAdded " + url
  console.log event
  if @inviter is false
    webrtc = this
    @pc.createAnswer (desc) ->
      webrtc.pc.setLocalDescription desc
      webrtc.sendJingleIQ desc.sdp

  @callback.startRemoteMedia url, @farParty  if @callback?

WebRtcJingle::onRemoteStreamRemoved = (event) ->
  url = webkitURL.createObjectURL(event.stream)
  console.log "onRemoteStreamRemoved " + url
  console.log event

WebRtcJingle::onStateChanged = (event) ->
  console.log "onStateChanged"
  console.log event

WebRtcJingle::sendJingleTerminateIQ = ->
  if @callback?
    id = "webrtc-jingle-" + Math.random().toString(36).substr(2, 9)
    jIQ = "<iq type='set' to='" + @farParty + "' id='" + id + "'>"
    jIQ = jIQ + "<jingle xmlns='urn:xmpp:jingle:1' action='session-terminate' initiator='" + @jid + "' sid='" + @sid + "'>"
    jIQ = jIQ + "<reason><success/></reason></jingle></iq>"
    @callback.sendPacket jIQ

WebRtcJingle::sendJingleIQ = (sdp) ->
  return  unless @callback?
  console.log "sendJingleIQ"
  console.log sdp
  action = (if @inviter then "session-initiate" else "session-accept")
  iq = ""
  id = "webrtc-jingle-" + Math.random().toString(36).substr(2, 9)
  iq += "<iq type='set' to='" + @farParty + "' id='" + id + "'>"
  iq += "<jingle xmlns='urn:xmpp:jingle:1' action='" + action + "' initiator='" + @jid + "' sid='" + @sid + "'>"
  iq += "<webrtc xmlns='http://webrtc.org'>" + sdp + "</webrtc>"
  iq += "</jingle></iq>"
  @callback.sendPacket iq

WebRtcJingle::textToXML = (text) ->
  doc = null
  if window["DOMParser"]
    parser = new DOMParser()
    doc = parser.parseFromString(text, "text/xml")
  else if window["ActiveXObject"]
    doc = new ActiveXObject("MSXML2.DOMDocument")
    doc.async = false
    doc.loadXML text
  else
    throw Error("No DOMParser object found.")
  doc.firstChild

WebRtcJingle::addJingleNodesCandidates = ->
  console.log "addJingleNodesCandidates"
  iq = ""
  id = "jingle-nodes-" + Math.random().toString(36).substr(2, 9)
  iq += "<iq type='get' to='" + "relay." + "webrtc.free-solutions.org" + "' id='" + id + "'>"
  iq += "<channel xmlns='http://jabber.org/protocol/jinglenodes#channel' protocol='udp' />"
  iq += "</iq>"
  @callback.sendPacket iq