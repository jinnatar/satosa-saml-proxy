FROM python:3.12-slim-bookworm

# runtime dependencies
# Run as uid:gid 999:999 to avoid conferring default UID 1000 permissions to key material
RUN set -eux; \
	groupadd -g 999 satosa; \
	useradd -m -g 999 -u 999 satosa; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		jq \
		libxml2-utils \
		xmlsec1 \
		git \
		patch \
	; \
	rm -rf /var/lib/apt/lists/*; \
	pip install --no-cache-dir \
		yq \
	;


# Install SATOSA from git latest since the latest release 8.4.0 lacks idpy_oidc_backend which is required for PKCE
RUN set -eux; \
	pip install --no-cache-dir \
		'satosa[idpy_oidc_backend] @ git+https://github.com/IdentityPython/SATOSA' \
	; \
	mkdir /etc/satosa; \
	chown -R satosa:satosa /etc/satosa

# Patch an ES256 issue in idpyoidc while not fixed upstream: https://github.com/IdentityPython/idpy-oidc/issues/110
COPY ES256.patch /tmp
RUN set -eux; \
	patch -p1 /usr/local/lib/python3.12/site-packages/idpyoidc/message/oidc/__init__.py /tmp/ES256.patch

WORKDIR /etc/satosa

# Preload bespoke ENV configurable config
COPY *.yaml /etc/satosa

ENTRYPOINT ["gunicorn"]
EXPOSE 80
USER satosa:satosa
CMD ["-b0.0.0.0:80","satosa.wsgi:app"]
