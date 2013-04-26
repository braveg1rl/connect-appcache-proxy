build:
	mkdir -p lib
	rm -rf lib/*
	node_modules/.bin/coffee --compile -m --output lib/ src/

watch:
	node_modules/.bin/coffee --watch --compile --output lib/ src/
	
test:
	node_modules/.bin/mocha

jumpstart:
	curl -u 'meryn' https://api.github.com/user/repos -d '{"name":"connect-appcache-proxy", "description":"A proxy for files listed in an appcache manifest.","private":false}'
	mkdir -p src
	touch src/connect-appcache-proxy.coffee
	mkdir -p test
	touch test/connect-appcache-proxy.coffee
	npm install
	git init
	git remote add origin git@github.com:meryn/connect-appcache-proxy
	git add .
	git commit -m "jumpstart commit."
	git push -u origin master

.PHONY: test