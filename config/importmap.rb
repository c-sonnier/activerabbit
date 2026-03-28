# Pin npm packages by running ./bin/importmap

pin "application"
pin "@hotwired/turbo-rails", to: "turbo.min.js"
pin "@hotwired/stimulus", to: "stimulus.min.js"
pin "@hotwired/stimulus-loading", to: "stimulus-loading.js"
pin "@rails/actioncable", to: "actioncable.esm.js"
pin_all_from "app/javascript/controllers", under: "controllers"
pin "chart.js/auto", to: "https://esm.sh/chart.js@4.4.1/auto"
pin "marked", to: "https://esm.sh/marked@12.0.2"
pin "highlight.js", to: "https://esm.sh/highlight.js@11.9.0"
pin "rrweb", to: "https://esm.sh/rrweb@2.0.0-alpha.17"
pin "rrweb-player", to: "https://esm.sh/rrweb-player@2.0.0-alpha.17"
pin "pako", to: "https://esm.sh/pako@2.1.0"
