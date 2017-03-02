

stop:
	docker stop jekyll || true

rm:stop
	docker rm jekyll || true

run:rm
	docker run -d --restart=always --name=jekyll --label=jekyll --volume=$(PWD):/srv/jekyll -p 8080:4000 jekyll/jekyll jekyll serve
