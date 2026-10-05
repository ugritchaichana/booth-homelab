import { Component, Input } from '@angular/core';
import { CommonModule } from '@angular/common';
import { InvoiceItem } from './billing.service';

@Component({
  selector: 'app-billing-summary',
  standalone: true,
  imports: [CommonModule],
  template: `
    <div class="billing-card" *ngIf="invoice">
      <h3>Invoice Details: {{ invoice.id }}</h3>
      <p>Order ID: #{{ invoice.orderId }}</p>
      <div class="line-item">Subtotal: {{ invoice.subtotal | currency:invoice.currency }}</div>
      <div class="line-item">Tax (7%): {{ invoice.tax | currency:invoice.currency }}</div>
      <div class="line-item total">Total Due: {{ invoice.total | currency:invoice.currency }}</div>
    </div>
  `,
  styles: [`
    .billing-card { border: 1px solid #ccc; padding: 1rem; border-radius: 8px; }
    .total { font-weight: bold; font-size: 1.2rem; }
  `]
})
export class BillingSummaryComponent {
  @Input() invoice: InvoiceItem | null = null;
}
