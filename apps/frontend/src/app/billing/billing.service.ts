import { Injectable } from '@angular/core';

export interface InvoiceItem {
  id: string;
  orderId: number;
  subtotal: number;
  tax: number;
  total: number;
  currency: string;
}

@Injectable({
  providedIn: 'root'
})
export class BillingService {
  readonly defaultTaxRate = 0.07;

  calculateTax(amount: number, rate: number = this.defaultTaxRate): number {
    if (amount < 0) return 0;
    return Math.round(amount * rate * 100) / 100;
  }

  generateInvoiceId(orderId: number): string {
    return `INV-${String(orderId).padStart(6, '0')}`;
  }

  createInvoice(orderId: number, subtotal: number, currency: string = 'USD'): InvoiceItem {
    const tax = this.calculateTax(subtotal);
    const total = Math.round((subtotal + tax) * 100) / 100;

    return {
      id: this.generateInvoiceId(orderId),
      orderId,
      subtotal,
      tax,
      total,
      currency
    };
  }
}
