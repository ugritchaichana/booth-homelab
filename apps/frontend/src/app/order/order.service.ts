import { Injectable } from '@angular/core';

export interface CheckoutResult {
  subtotal: number;
  discount: number;
  taxableAmount: number;
  tax: number;
  grandTotal: number;
  voucherApplied: string | null;
}

@Injectable({
  providedIn: 'root'
})
export class OrderService {
  private readonly validVouchers: Record<string, { type: 'fixed' | 'percent'; value: number }> = {
    SAVE10: { type: 'fixed', value: 10 },
    VIP20: { type: 'percent', value: 0.20 }
  };

  validateVoucher(code: string): boolean {
    return !!this.validVouchers[code.toUpperCase()];
  }

  calculateCheckout(subtotal: number, voucherCode?: string): CheckoutResult {
    if (subtotal < 0) subtotal = 0;
    let discount = 0;
    let appliedCode: string | null = null;

    if (voucherCode && this.validateVoucher(voucherCode)) {
      appliedCode = voucherCode.toUpperCase();
      const voucher = this.validVouchers[appliedCode];
      if (voucher.type === 'fixed') {
        discount = Math.min(voucher.value, subtotal);
      } else if (voucher.type === 'percent') {
        discount = Math.round(subtotal * voucher.value * 100) / 100;
      }
    }

    const taxableAmount = Math.max(0, Math.round((subtotal - discount) * 100) / 100);
    const tax = Math.round(taxableAmount * 0.07 * 100) / 100;
    const grandTotal = Math.round((taxableAmount + tax) * 100) / 100;

    return {
      subtotal,
      discount,
      taxableAmount,
      tax,
      grandTotal,
      voucherApplied: appliedCode
    };
  }
}
