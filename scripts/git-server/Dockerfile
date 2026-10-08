# Tiny read-only git "smart HTTP" server (git-http-backend behind lighttpd).
# Used by the kind bootstrap and CI so Argo CD can sync from a *local* checkout,
# before (or without) pushing to GitHub.
FROM alpine:3.22
RUN apk add --no-cache git git-daemon lighttpd \
 && git config --system --add safe.directory '*'
COPY lighttpd.conf /etc/lighttpd/lighttpd.conf
EXPOSE 8080
CMD ["lighttpd", "-D", "-f", "/etc/lighttpd/lighttpd.conf"]
