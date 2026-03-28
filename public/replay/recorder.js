/**
 * ActiveRabbit Session Replay Recorder v1.0.0
 *
 * Usage:
 *   <script>
 *     window.ActiveRabbitReplay = {
 *       token: "YOUR_PROJECT_TOKEN",
 *       replaysSessionSampleRate: 0.1,   // 10% of all sessions
 *       replaysOnErrorSampleRate: 1.0,   // 100% of sessions with errors
 *       maskAllText: false,
 *       maskAllInputs: true,
 *       blockAllMedia: false
 *     };
 *   </script>
 *   <script src="https://activerabbit.com/replay/recorder.js" defer crossorigin="anonymous"></script>
 */
(function(){
  var cfg = window.ActiveRabbitReplay || {};
  var T = cfg.token || document.currentScript.getAttribute("data-token");
  if (!T) return;

  var origin = document.currentScript.src.split("/replay/")[0];
  var E = (cfg.endpoint || origin) + "/api/v1/replay_sessions";

  // Two-tier sampling (Sentry-style)
  var sessionRate = cfg.replaysSessionSampleRate != null ? cfg.replaysSessionSampleRate : 1.0;
  var errorRate = cfg.replaysOnErrorSampleRate != null ? cfg.replaysOnErrorSampleRate : 1.0;

  var sessionSampled = Math.random() < sessionRate;
  var errorSampled = Math.random() < errorRate;

  // Skip entirely if neither rate selected this session
  if (!sessionSampled && !errorSampled) return;

  var s = document.createElement("script");
  s.src = origin + "/rrweb.min.js";
  s.crossOrigin = "anonymous";
  s.onload = function(){
    var rid = crypto.randomUUID(), sid = crypto.randomUUID(),
        evts = [], t0 = Date.now(), sa = new Date().toISOString(), lc = 0,
        hasError = false, sent = false;

    rrweb.record({
      emit: function(e){ evts.push(e) },
      sampling: cfg.sampling || { mousemove: 50, scroll: 150, input: "last" },
      maskAllInputs: cfg.maskAllInputs !== false,
      maskTextSelector: cfg.maskAllText ? "*" : null,
      blockSelector: cfg.blockAllMedia ? "img,svg,video,canvas,object,embed" : null,
      maskInputOptions: Object.assign(
        { password: true, email: true, tel: true },
        cfg.maskInputOptions || {}
      ),
      maskTextClass: cfg.maskTextClass || "rr-mask",
      blockClass: cfg.blockClass || "rr-block"
    });

    // Listen for errors to trigger error-sampled recording
    function onError(){
      hasError = true;
      // If this session wasn't session-sampled but IS error-sampled, send immediately
      if (!sessionSampled && errorSampled && !sent) {
        send(false);
      }
    }
    window.addEventListener("error", onError);
    window.addEventListener("unhandledrejection", onError);

    function send(sync){
      // Only send if: session-sampled OR (error-sampled AND had an error)
      if (!sessionSampled && !(errorSampled && hasError)) return;
      if (evts.length < 2 || evts.length === lc) return;
      lc = evts.length;
      sent = true;
      var b = JSON.stringify({
        replay_id: rid, session_id: sid, events: evts,
        started_at: sa, duration_ms: Date.now() - t0,
        url: location.href, user_agent: navigator.userAgent,
        viewport_width: innerWidth, viewport_height: innerHeight,
        environment: cfg.environment || "production",
        trigger_type: hasError ? "error" : "session",
        sdk_version: "1.0.0", rrweb_version: "2.0.0-alpha.4"
      });
      try { fetch(E, { method: "POST", headers: { "Content-Type": "application/json", "X-Project-Token": T }, body: b, keepalive: !!sync }).catch(function(){}); } catch(e) {}
    }

    setInterval(send, cfg.flushInterval || 30000);
    document.addEventListener("visibilitychange", function(){ send(true) });
    window.addEventListener("beforeunload", function(){ send(true) });
  };
  document.head.appendChild(s);
})();
