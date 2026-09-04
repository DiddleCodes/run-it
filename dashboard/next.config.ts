import type { NextConfig } from "next";
import { withSentryConfig } from "@sentry/nextjs/config";

const nextConfig: NextConfig = {
  /* config options here */
};

// Task 36: no org/project/authToken configured — source-map upload is
// simply skipped (silent: true keeps that from being a noisy build
// warning); error capture itself doesn't depend on it.
export default withSentryConfig(nextConfig, {
  silent: true,
});
