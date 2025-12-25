FROM hairyhenderson/gomplate:stable AS gomplate
FROM nginx:alpine

COPY --from=gomplate /gomplate /usr/local/bin/gomplate

COPY default.conf.template /etc/nginx/templates/default.conf.template
COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
