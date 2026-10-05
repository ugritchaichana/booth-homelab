import { ComponentFixture, TestBed } from '@angular/core/testing';
import { BillingSummaryComponent } from './billing-summary.component';
import { InvoiceItem } from './billing.service';

describe('BillingSummaryComponent (Jest Component Tests)', () => {
  let component: BillingSummaryComponent;
  let fixture: ComponentFixture<BillingSummaryComponent>;

  const mockInvoice: InvoiceItem = {
    id: 'INV-000088',
    orderId: 88,
    subtotal: 500.0,
    tax: 35.0,
    total: 535.0,
    currency: 'USD'
  };

  beforeEach(async () => {
    await TestBed.configureTestingModule({
      imports: [BillingSummaryComponent]
    }).compileComponents();

    fixture = TestBed.createComponent(BillingSummaryComponent);
    component = fixture.componentInstance;
  });

  it('should create the component', () => {
    expect(component).toBeTruthy();
  });

  it('should render invoice details when input is provided', () => {
    component.invoice = mockInvoice;
    fixture.detectChanges();

    const compiled = fixture.nativeElement as HTMLElement;
    expect(compiled.querySelector('h3')?.textContent).toContain('INV-000088');
    expect(compiled.querySelector('.total')?.textContent).toContain('535.00');
  });

  it('should not render billing-card when invoice is null', () => {
    component.invoice = null;
    fixture.detectChanges();

    const card = fixture.nativeElement.querySelector('.billing-card');
    expect(card).toBeNull();
  });
});
