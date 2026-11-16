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
