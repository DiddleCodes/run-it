import { Controller, Get, Header } from '@nestjs/common';

/**
 * PAYSTACK_CALLBACK_URL. Paystack sends the in-app checkout here when a
 * top-up finishes; the app's payment screen watches for this address and
 * closes before anything loads. This page only shows if the checkout ever
 * finishes outside the app (e.g. in a browser). It confirms nothing —
 * whether money arrived is decided by the webhook and verification, never
 * by reaching this URL — so it reads no query parameters.
 */
@Controller('payments')
export class PaymentCallbackController {
  @Get('callback')
  @Header('Content-Type', 'text/html; charset=utf-8')
  @Header('Cache-Control', 'no-store')
  callback(): string {
    return `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Bridgit payment</title></head>
<body style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:420px;margin:15vh auto;padding:0 24px;text-align:center;color:#1a1a1a">
<h1 style="font-size:22px;margin:0 0 12px">Payment received</h1>
<p style="font-size:15px;line-height:1.5;color:#555;margin:0">You can close this page and go back to the Bridgit app. Your wallet updates there once Paystack confirms the payment.</p>
</body></html>`;
  }
}
