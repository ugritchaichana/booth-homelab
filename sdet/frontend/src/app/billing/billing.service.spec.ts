import { TestBed } from '@angular/core/testing';
import { BillingService } from './billing.service';

describe('BillingService (Jest Unit Tests)', () => {
  let service: BillingService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [BillingService]
    });
    service = TestBed.inject(BillingService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  describe('calculateTax', () => {
    it('should calculate 7% tax accurately on standard subtotal', () => {
      const tax = service.calculateTax(100.0);
      expect(tax).toBe(7.0);
    });

    it('should round tax to two decimal places', () => {
      const tax = service.calculateTax(99.95, 0.07);
      expect(tax).toBe(7.0);
    });

    it('should return 0 for negative amounts', () => {
      expect(service.calculateTax(-50)).toBe(0);
    });
  });

  describe('generateInvoiceId', () => {
    it('should format invoice ID with 6-digit zero padding', () => {
      expect(service.generateInvoiceId(42)).toBe('INV-000042');
      expect(service.generateInvoiceId(100204)).toBe('INV-100204');
    });
  });

  describe('createInvoice', () => {
    it('should generate complete invoice object with correct totals', () => {
      const invoice = service.createInvoice(101, 200.0, 'USD');

      expect(invoice).toEqual({
        id: 'INV-000101',
        orderId: 101,
        subtotal: 200.0,
        tax: 14.0,
        total: 214.0,
        currency: 'USD'
      });
    });
  });
});
