/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  // RainbowKit + wagmi need to bundle some ESM-only deps.
  transpilePackages: ["@rainbow-me/rainbowkit"],
};

export default nextConfig;
