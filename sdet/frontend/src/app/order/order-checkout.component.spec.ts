import { ComponentFixture, TestBed } from '@angular/core/testing';
import { FormsModule } from '@angular/forms';
import { OrderCheckoutComponent } from './order-checkout.component';
import { OrderService } from './order.service';

describe('OrderCheckoutComponent (Jest Component Tests)', () => {
  let component: OrderCheckoutComponent;
  let fixture: ComponentFixture<OrderCheckoutComponent>;

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [OrderCheckoutComponent, FormsModule],
      providers: [OrderService]
    }).compileComponents();

    fixture = TestBed.createComponent(OrderCheckoutComponent);
    component = fixture.componentInstance;
    fixture.detectChanges();
  });

  it('should create the checkout component', () => {
    expect(component).toBeTruthy();
  });

  it('should calculate checkout summary when button is clicked', () => {
    component.subtotal = 100;
    component.voucherCode = 'SAVE10';
    component.onCheckout();
    fixture.detectChanges();

    expect(component.checkoutResult).toBeTruthy();
    expect(component.checkoutResult?.discount).toBe(10);
    expect(component.checkoutResult?.grandTotal).toBe(96.30);

    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector('.grand-total')?.textContent).toContain('96.30');
    expect(compiled.querySelector('.error-alert')).toBeNull();
  });

  it('should display error message when invalid voucher code is entered', () => {
    component.subtotal = 100;
    component.voucherCode = 'FAKECODE';
    component.onCheckout();
    fixture.detectChanges();

    const compiled = fixture.nativeElement as HTMLElement;
    expect(component.errorMessage).toContain('Invalid voucher code: FAKECODE');
    expect(compiled.querySelector('.error-alert')?.textContent).toContain('Invalid voucher code: FAKECODE');
  });
});
