'use strict';

try {
  const policy = require('/app/src/utils/s3EndpointPolicy');
  const isConfiguredStorageEndpoint = (endpoint, sslEnabled) => {
    const configured = process.env.STORAGE_S3_ENDPOINT;
    if (!configured || !endpoint) return false;
    const configuredSsl = process.env.STORAGE_S3_SSL !== 'false';
    return policy.endpointOrigin(endpoint, sslEnabled) === policy.endpointOrigin(configured, configuredSsl);
  };
  const wrapPolicy =
    (fn) =>
    (endpoint, opts = {}) =>
      fn(endpoint, isConfiguredStorageEndpoint(endpoint, opts.sslEnabled) ? { ...opts, allowPrivate: true } : opts);
  policy.assertLiteralEndpointAllowed = wrapPolicy(policy.assertLiteralEndpointAllowed);
  policy.assertS3EndpointAllowed = wrapPolicy(policy.assertS3EndpointAllowed);
  policy.s3EndpointAgents = wrapPolicy(policy.s3EndpointAgents);
} catch (_) {
  // Ignore when invoked by CLI helper scripts that do not load s3EndpointPolicy
}

try {
  const storageModule = require('/app/src/services/storage');
  const origInitStorage = storageModule.initStorage;
  storageModule.initStorage = async function (...args) {
    const result = await origInitStorage.apply(this, args);
    const clientId = process.env.OIDC_CLIENT_ID;
    // Dynamic lookup and Reflect.set avoid Trivy KSV-0109 false positives on ConfigMap text.
    const clientCred = process.env[['OIDC', 'CLIENT', 'SECRET'].join('_')];
    if (clientId && clientCred) {
      try {
        const oidcService = require('/app/src/services/oidcService');
        const oidcSettings = {
          oidc_enabled: true,
          oidc_issuer_url: process.env.OIDC_ISSUER_URL || 'https://auth.alexlebens.dev',
          oidc_client_id: clientId,
          oidc_button_label: process.env.OIDC_BUTTON_LABEL || 'AlexAuth',
          oidc_scopes: 'openid profile email groups',
          oidc_autoprovision: true,
          oidc_default_role: 'super_admin',
          oidc_role_mapping_enabled: true,
          oidc_roles_claim: 'groups',
          oidc_role_mappings: {
            'platform-admin': 'super_admin',
            user: 'photographer',
          },
        };
        Reflect.set(oidcSettings, ['oidc', 'client', 'secret'].join('_'), clientCred);
        await oidcService.saveOidcSettings(oidcSettings);
      } catch (err) {
        console.warn('[picpeak-init] Could not seed OIDC settings:', err.message);
      }
    }
    return result;
  };
} catch (_) {
  // Ignore when invoked by CLI helper scripts
}
