import { Component } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { OrderService, CheckoutResult } from './order.service';

@Component({
  selector: 'app-order-checkout',
  standalone: true,
  imports: [CommonModule, FormsModule],
  template: `
    <div class="checkout-container">
      <h2>Order Checkout</h2>
      <div class="input-group">
        <label for="subtotal">Subtotal ($):</label>
        <input id="subtotal" type="number" [(ngModel)]="subtotal" min="0" />
      </div>
      <div class="input-group">
        <label for="voucher">Voucher Code:</label>
        <input id="voucher" type="text" [(ngModel)]="voucherCode" placeholder="e.g. SAVE10, VIP20" />
      </div>
      <button id="checkout-btn" (click)="onCheckout()">Apply & Checkout</button>

      <div *ngIf="errorMessage" class="error-alert">{{ errorMessage }}</div>

      <div *ngIf="checkoutResult" class="summary-card">
        <p>Subtotal: {{ checkoutResult.subtotal | currency }}</p>
        <p *ngIf="checkoutResult.discount > 0" class="discount">
          Discount ({{ checkoutResult.voucherApplied }}): -{{ checkoutResult.discount | currency }}
        </p>
        <p>Tax (7%): {{ checkoutResult.tax | currency }}</p>
        <h3 class="grand-total">Total: {{ checkoutResult.grandTotal | currency }}</h3>
      </div>
    </div>
  `,
  styles: [`
    .checkout-container { max-width: 400px; padding: 1.5rem; border: 1px solid #ddd; border-radius: 8px; }
    .input-group { margin-bottom: 1rem; }
    .error-alert { color: red; margin-top: 0.5rem; }
    .discount { color: green; }
    .grand-total { color: #0066cc; }
  `]
})
export class OrderCheckoutComponent {
  subtotal: number = 100;
  voucherCode: string = '';
  errorMessage: string = '';
  checkoutResult: CheckoutResult | null = null;

  constructor(private orderService: OrderService) {}

  onCheckout(): void {
    this.errorMessage = '';
    if (this.voucherCode && !this.orderService.validateVoucher(this.voucherCode)) {
      this.errorMessage = `Invalid voucher code: ${this.voucherCode}`;
    }
    this.checkoutResult = this.orderService.calculateCheckout(this.subtotal, this.voucherCode);
  }
}
