class ReplayRecorderController < ActionController::Base
  # Public endpoint — no auth required. The token in the query string identifies the project.
  skip_forgery_protection

  # GET /replay/recorder.js?token=xxx
  def script
    token = params[:token]

    unless token.present?
      head :bad_request
      return
    end

    endpoint = "#{request.base_url}/api/v1/replay_sessions"

    js = <<~JS
      (function(){
        var s=document.createElement("script");
        s.src="#{request.base_url}/rrweb.min.js";
        s.onload=function(){
          var T="#{token}",E="#{endpoint}",
              rid=crypto.randomUUID(),sid=crypto.randomUUID(),
              evts=[],t0=Date.now(),sa=new Date().toISOString(),lc=0;

          rrweb.record({
            emit:function(e){evts.push(e)},
            sampling:{mousemove:50,scroll:150,input:"last"},
            maskInputOptions:{password:true}
          });

          function send(sync){
            if(evts.length<2||evts.length===lc)return;
            lc=evts.length;
            var b=JSON.stringify({
              replay_id:rid,session_id:sid,events:evts,
              started_at:sa,duration_ms:Date.now()-t0,
              url:location.href,user_agent:navigator.userAgent,
              viewport_width:innerWidth,viewport_height:innerHeight,
              environment:"production",sdk_version:"1.0.0",
              rrweb_version:"2.0.0-alpha.4"
            });
            fetch(E,{method:"POST",headers:{"Content-Type":"application/json","X-Project-Token":T},body:b,keepalive:!!sync}).catch(function(){});
          }

          setInterval(send,30000);
          document.addEventListener("visibilitychange",function(){send(true)});
          window.addEventListener("beforeunload",function(){send(true)});
        };
        document.head.appendChild(s);
      })();
    JS

    response.headers["Cache-Control"] = "public, max-age=3600"
    render plain: js, content_type: "application/javascript"
  end
end
