# SATOSA based SAML to Kanidm OIDC proxy

i.e. How to connect legacy web apps that only support SAML to be backed by Kanidm OIDC. While the configs in this repo can be educational for rolling your own SATOSA setup, an opinionated ENV configurable container image is also provided.

> [!CAUTION]
> This is an early version that only supports a 1:1 proxy config where a single SAML supporting web service auths via a single OIDC endpoint.
> The intent is to morph into a "v2" that allows a dynamic mapping of multiple systems to multiple OIDC endpoints via a single SAML proxy. The simpler version will be preserved for educational purposes but is intended to become "legacy".

## TODO items on the roadmap
1. Add log level configuration via ENV. It's now hardcoded to debug.
2. Rewrite env config & the SATOSA configs for dynamic routing so that multiple apps can be routed to different OIDC clients. In the meanwhile you can configure multiple apps to use the same proxy, but then you can't control via claim maps on the Kanidm side who is eligible for what app.
3. Get rid of the `ES256.patch` hack once idpyoidc no longer forces RS256.

## Step by step guides for usage

SAML is a bit *involved* so we need to prep a persistent certificate and provide metadata for the system you will auth for. We'll first cover generic steps and then go over them again with a practical example setting up SSO for Ceph.

### Generic steps
1. Generate your SAML2 certs, be sure to select the validity days and provide your own SN matching the proxy domain.
   ```shell
   openssl req -x509 -sha256 -nodes -days 365 -newkey rsa:2048 \
        -keyout saml.key -out saml.crt -subj "/SN=saml.example.com/"
   ```
1. Give read access to your key: `chown :999 saml.key && chmod g+r saml.key` .. This way SATOSA is limited to only read.
1. Get your target SAML side system's metadata XML file. How to do this is specific to the app you're setting up! This isn't just a static file, it will need details specific to your installation so it's common to have an endpoint you can `curl` to generate it. You may not be able to generate it until you've registered the proxy's metadata on the app side, in this case leave `SAML_METADATA=dummy-metadata.xml` to get the proxy running first and then circle back once you get the real data.
1. Once you have your metadata XML file, make it available to your container, for example via a volume. The dummy data is already available.
2. Configure the ENV variables that will tweak the provided SATOSA configs. You can edit the provided `example.env` file and feed it to Docker via the `--env-file` flag. Make sure to **not** quote values if using that flag. Explanations below:
   ```shell
   ENCRYPTION_KEY=0xDEADBEEF  # Key used to encrypt state in transit. Could generate with `openssl rand -base64 32`  
   OIDC_CLIENT_ID=your-client-id  # The OIDC client id in Kanidm is the name of the integration, for example `ceph`  
   OIDC_CLIENT_SECRET=your-oidc-client-secret  
   OIDC_ISSUER_URL=https://idm.example.com/oauth2/openid/your-client-id  # Full URL to the discovery endpoint  
   OIDC_NAME=unique_oidc_name  # A unique id used for this OIDC backend in SATOSA. Uniqueness becomes relevant if you configure multiple on the same proxy.  
   PROXY_BASE_URL=https://saml.example.com  # Where your proxy lives. **must** be https, must be the root of a host, must match the CN in your cert from step 1.  
   SAML_METADATA="dummy-metadata.xml"  # A path to your app SAML metadata file. The working directory of the provided image is `/etc/satosa` so the relative path example here would expect the file to be on the container at `/etc/satosa/dummy-metadata.xml`. If you can't get this until the proxy is running and you've registered it in the app, use dummy-metadata.xml as a workaround to boot the proxy without it.  
   SAML_NAME=unique_saml_name  # A unique id used for this SAML frontend in SATOSA. Uniqueness becomes relevant if you configure multiple on the same proxy.
   ```
3. Launch the proxy. This depends on your container orchestration, but a simple testing example is provided below. **This is not enough, you need to get https working which is outside the scope of this guide.
   ```shell
   # Assuming a reverse proxy will handle TLS from https://saml.example.com
   docker run --rm -it -p 8080:80 \
    --env-file example.env \
    -v $PWD/saml.crt:/etc/satosa/saml.crt -v $PWD/saml.key:/etc/satosa/saml.key  \
    -v $PWD/your-app-metadata.xml:/etc/satosa/your-app-metadata.xml \
    ghcr.io/jinnatar/satosa-saml-proxy:latest

   # Let gunicorn handle TLS, otherwise the same, just add at the end after the image name:
    --keyfile=<https key> --certfile=<https cert>
   ```
4. Register the proxy with your app to enable SAML based SSO. This is highly dependent on your app but the proxy endpoint that spits out your bespoke metadata will be: `https://saml.example.com/unique_saml_name/metadata.xml`
5. Test and monitor your app, proxy and iDP logs if anything goes wrong!

### Practical example: Ceph SSO via Kanidm
1. Pre-create your users in Ceph to give them the correct authz. In this example we'll use short usernames for simplicity so that needs to match.
1. Create your Kanidm OIDC configuration the usual way, no need to disable PKCE!
   ```
   kanidm system oauth2 create ceph Ceph https://saml.example.com  # **Important**, give the proxy URL here.
   kanidm system oauth2 prefer-short-username ceph # Use short usernames for convenience
   kanidm system oauth2 update-scope-map ceph ceph_admins openid profile email  # Create the scope map, don't forget to create the group and add your Ceph admins to it.
   kanidm system oauth2 show-basic-secret ceph  # Get your client_secret for use later on.
   ```
1. Create your SAML2 certs and set their permissions as per the generic steps above, nothing special here.
1. We can't get Ceph to spit out it's metadata XML before the proxy is functioning so we skip ahead.
1. Config your ENV variables into a new env file, `ceph.env`. If you don't change the ENCRYPTION_KEY value you deserve everything you get as a result.
   ```shell
   ENCRYPTION_KEY=+OSDGTYdWxesiUwcMEzaGzwCx81YHhzOFgsitMn9A/c=
   OIDC_CLIENT_ID=ceph
   OIDC_CLIENT_SECRET=# You got this above from kanidm
   OIDC_ISSUER_URL=https://idm.example.com/oauth2/openid/ceph
   OIDC_NAME=oidc_ceph
   PROXY_BASE_URL=https://saml.example.com
   SAML_METADATA=dummy-metadata.xml
   SAML_NAME=saml_ceph
   ```
1. Launch the proxy with your configured ENV:
   ```shell
   docker run --rm -it -p 8080:80 \
    --env-file ceph.env \
    -v $PWD/saml.crt:/etc/satosa/saml.crt -v $PWD/saml.key:/etc/satosa/saml.key  \
    ghcr.io/jinnatar/satosa-saml-proxy:latest
   ```
1. Register the proxy with Ceph, giving it the Ceph URL, SAML metadata endpoint and an attribute field name to expect for the username.
   ```shell
   ceph dashboard sso setup saml2 https://ceph.example.com https://saml.example.com/saml_ceph/metadata.xml urn:oid:0.9.2342.19200300.100.1.1
   ```
1. Assuming registration was succesful, we can now get the Ceph side SAML metadata:
   ```shell
   curl https://ceph.example.com/auth/saml2/metadata > ceph-metadata.xml
   ```
   And can now amend `ceph.env` with: `SAML_METADATA=ceph-metadata.xml` and restart the proxy, this time adding an extra mount for the real Ceph metadata:
   ```shell
   docker run --rm -it -p 8080:80 \
    --env-file ceph.env \
    -v $PWD/saml.crt:/etc/satosa/saml.crt -v $PWD/saml.key:/etc/satosa/saml.key  \
    -v $PWD/ceph-metadata.xml:/etc/satosa/ceph-metadata.xml \
    ghcr.io/jinnatar/satosa-saml-proxy:latest
    ```

1. Restart the proxy and go test Ceph SSO!
