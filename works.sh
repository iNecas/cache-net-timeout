cat <<EOF | scl enable tfm -- rails console
   conf.return_format = ""
   require 'logger'
   require 'net/http'
   log = Logger.new(STDOUT)
   log.info("Started thread #{\$\$}")
   url = URI.parse('http://127.0.0.1/')
   iteration = 0
   cycle = 0
   while true        
     begin
       cycle += 1
       if cycle == 1000
         iteration += 1
         cycle = 0
         log.info "=== iteration #{iteration}k"
       end
       Rails.cache.fetch('hello') { nil }
       Net::HTTP.get_response(url)
     rescue Exception => e
       log.info "Error at iteration #{iteration * 1000 + cycle}"
       log.info "#{e.class} #{e.message}"
       log.info e.backtrace.join("\n")
     end
   end
EOF
