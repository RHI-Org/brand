# Brand by Experience Plus

Personal-brand strategy, photography, video, and content systems. Scandinavian, mobile-first React/Vite site hosted on GitHub Pages at `brand.experienceplus.ai`.

## Development

```bash
npm install
npm run dev
npm run build
```

## Payments

The package buttons currently open a clearly labeled Stripe Checkout preview. To activate payments, implement `POST /api/create-checkout-session`, map package names to server-owned Stripe Price IDs, and replace the preview action with a redirect to the returned Checkout URL. Never expose the Stripe secret key in this static site.

## Media

All media used by the deployed site is stored under `public/media` with poster frames in `public/images`. Background video is muted, looping, inline on mobile, and has an accessible pause control.
