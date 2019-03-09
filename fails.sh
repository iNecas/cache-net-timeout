#!/usr/bin/env bash

# seems like content of the tmp/cache is relevant here reverting to the git state
git checkout -- tmp/cache
cat <<EOF | rails console
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
       Rails.cache.write('hello', nil)
       Net::HTTP.get_response(url)
     rescue => e
       log.error("#{e.class}:#{e.message}")
       log.error("#{e.backtrace.join("\n")}")
       exit
     end
   end
EOF
