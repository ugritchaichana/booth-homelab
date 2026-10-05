import { TestBed } from '@angular/core/testing';
import { OrderService } from './order.service';

describe('OrderService (Jest Unit Tests)', () => {
  let service: OrderService;

  beforeEach(() => {
    TestBed.configureTestingModule({
      providers: [OrderService]
    });
    service = TestBed.inject(OrderService);
  });

  it('should be created', () => {
    expect(service).toBeTruthy();
  });

  describe('validateVoucher', () => {
    it('should return true for valid voucher codes (case-insensitive)', () => {
      expect(service.validateVoucher('SAVE10')).toBe(true);
      expect(service.validateVoucher('save10')).toBe(true);
      expect(service.validateVoucher('VIP20')).toBe(true);
    });

    it('should return false for unknown voucher codes', () => {
      expect(service.validateVoucher('INVALID99')).toBe(false);
      expect(service.validateVoucher('')).toBe(false);
    });
  });

  describe('calculateCheckout', () => {
    it('should calculate standard checkout without voucher correctly', () => {
      const res = service.calculateCheckout(100.0);
      expect(res.subtotal).toBe(100.0);
      expect(res.discount).toBe(0);
      expect(res.taxableAmount).toBe(100.0);
      expect(res.tax).toBe(7.0);
      expect(res.grandTotal).toBe(107.0);
      expect(res.voucherApplied).toBeNull();
    });

    it('should apply fixed discount voucher (SAVE10) correctly', () => {
      const res = service.calculateCheckout(100.0, 'SAVE10');
      expect(res.discount).toBe(10);
      expect(res.taxableAmount).toBe(90.0);
      expect(res.tax).toBe(6.30);
      expect(res.grandTotal).toBe(96.30);
      expect(res.voucherApplied).toBe('SAVE10');
    });

    it('should apply percentage discount voucher (VIP20) correctly', () => {
      const res = service.calculateCheckout(200.0, 'VIP20');
      expect(res.discount).toBe(40.0);
      expect(res.taxableAmount).toBe(160.0);
      expect(res.tax).toBe(11.20);
      expect(res.grandTotal).toBe(171.20);
      expect(res.voucherApplied).toBe('VIP20');
    });

    it('should ignore invalid voucher code and proceed with standard checkout', () => {
      const res = service.calculateCheckout(50.0, 'BOGUS');
      expect(res.discount).toBe(0);
      expect(res.grandTotal).toBe(53.50);
      expect(res.voucherApplied).toBeNull();
    });

    it('should clamp discount when fixed voucher exceeds subtotal', () => {
      const res = service.calculateCheckout(5.00, 'SAVE10');
      expect(res.discount).toBe(5.00);
      expect(res.taxableAmount).toBe(0.00);
      expect(res.tax).toBe(0.00);
      expect(res.grandTotal).toBe(0.00);
      expect(res.voucherApplied).toBe('SAVE10');
    });

    it('should clamp negative subtotal to zero', () => {
      const res = service.calculateCheckout(-10);
      expect(res.subtotal).toBe(0);
      expect(res.discount).toBe(0);
      expect(res.taxableAmount).toBe(0.00);
      expect(res.tax).toBe(0.00);
      expect(res.grandTotal).toBe(0.00);
      expect(res.voucherApplied).toBeNull();
    });

    it('should accurately round taxable amount for percentage discount with fractional cents', () => {
      const res = service.calculateCheckout(33.33, 'VIP20');
      expect(res.discount).toBe(6.67);
      expect(res.taxableAmount).toBe(26.66);
      expect(res.tax).toBe(1.87);
      expect(res.grandTotal).toBe(28.53);
      expect(res.voucherApplied).toBe('VIP20');
    });
  });
});
