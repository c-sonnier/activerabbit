import { Controller } from "@hotwired/stimulus"

// Session replay player v4
export default class extends Controller {
  static values = { url: String }

  async connect() {
    if (!this.urlValue) {
      this.showMessage("No replay data available")
      return
    }

    try {
      const response = await fetch(this.urlValue)
      if (!response.ok) throw new Error("HTTP " + response.status)

      const compressed = await response.arrayBuffer()
      const decompressed = await this.decompressZlib(compressed)
      const events = JSON.parse(decompressed)

      if (events.length < 2) {
        this.showMessage("Not enough events to replay")
        return
      }

      await this.waitForRrweb()

      const meta = events.find(function(e) { return e.type === 4 })
      const recW = (meta && meta.data && meta.data.width) || 1920
      const recH = (meta && meta.data && meta.data.height) || 1080
      const containerW = this.element.clientWidth || 800
      const scale = (containerW / recW) * 0.8
      const scaledH = Math.ceil(recH * scale)

      this.element.innerHTML = ''
      this.element.style.width = '100%'
      this.element.style.height = scaledH + 'px'
      this.element.style.overflow = 'hidden'
      this.element.style.background = '#111827'
      this.element.style.borderRadius = '8px'
      this.element.style.position = 'relative'

      var mount = document.createElement('div')
      mount.style.transform = 'scale(' + scale + ')'
      mount.style.transformOrigin = 'top left'
      mount.style.width = recW + 'px'
      mount.style.height = recH + 'px'
      mount.style.position = 'absolute'
      mount.style.top = '0'
      mount.style.left = '0'
      this.element.appendChild(mount)

      this.player = new window.rrweb.Replayer(events, {
        root: mount,
        skipInactive: true,
        showWarning: false,
        speed: 4
      })

      this.addControls()

    } catch (error) {
      console.error('[ReplayPlayer]', error)
      this.showMessage('Failed to load: ' + error.message)
    }
  }

  async decompressZlib(compressed) {
    var data = new Uint8Array(compressed)
    if (typeof DecompressionStream !== 'undefined') {
      var formats = ['deflate', 'raw']
      for (var i = 0; i < formats.length; i++) {
        try {
          var ds = new DecompressionStream(formats[i])
          var w = ds.writable.getWriter()
          w.write(data); w.close()
          var chunks = [], r = ds.readable.getReader()
          while (true) { var result = await r.read(); if (result.done) break; chunks.push(result.value) }
          var totalLen = chunks.reduce(function(s,c){ return s+c.length }, 0)
          var merged = new Uint8Array(totalLen)
          var off = 0
          for (var j = 0; j < chunks.length; j++) { merged.set(chunks[j], off); off += chunks[j].length }
          return new TextDecoder().decode(merged)
        } catch(e) {}
      }
    }
    try { var p = await import('pako'); return p.inflate(data, {to:'string'}) } catch(e) {}
    throw new Error('Could not decompress')
  }

  waitForRrweb() {
    return new Promise(function(res, rej) {
      var n = 0
      var check = function() {
        if (window.rrweb && window.rrweb.Replayer) res()
        else if (n++ < 50) setTimeout(check, 200)
        else rej(new Error('rrweb not loaded'))
      }
      check()
    })
  }

  addControls() {
    var el = document.createElement('div')
    el.className = 'flex items-center gap-3 mt-3'
    el.innerHTML = '<button data-action="click->replay-player#play" class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-indigo-600 text-white text-sm font-medium rounded-md hover:bg-indigo-700">Play</button><button data-action="click->replay-player#pause" class="inline-flex items-center gap-1.5 px-3 py-1.5 bg-gray-200 text-gray-700 text-sm font-medium rounded-md hover:bg-gray-300">Pause</button><select data-action="change->replay-player#setSpeed" class="border border-gray-300 rounded-md text-sm py-1.5 px-2"><option value="1">1x</option><option value="2">2x</option><option value="4" selected>4x</option><option value="8">8x</option></select>'
    this.element.parentNode.appendChild(el)
  }

  play() { if (this.player) this.player.play() }
  pause() { if (this.player) this.player.pause() }
  setSpeed(e) { if (this.player) this.player.setConfig({ speed: parseInt(e.target.value) }) }
  showMessage(t) { this.element.innerHTML = '<div class="flex items-center justify-center text-gray-400" style="min-height:200px"><p class="text-sm">' + t + '</p></div>' }
  disconnect() { if (this.player) { this.player.pause(); this.player = null } }
}
