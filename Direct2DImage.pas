unit Direct2DImage;

interface

uses
  Winapi.Windows,
  System.Classes,
  Vcl.Graphics, Vcl.Controls;

type
  TWICPicture = class(TPicture)
  protected
    procedure FindGraphicClass(const Context: TFindGraphicClassContext;
      var GraphicClass: TGraphicClass); override;
  public
    procedure Assign(Source: TPersistent); override;
  end;

  TDirect2DImage = class sealed (TGraphicControl)
  strict private
    FPicture: TWicPicture;
    FStretch: Boolean;
    FCenter: Boolean;
    FDrawing: Boolean;
    FProportional: Boolean;
    procedure PictureChanged(Sender: TObject);
    procedure SetCenter(Value: Boolean);
    procedure SetPicture(Value: TWicPicture);
    procedure SetStretch(Value: Boolean);
    procedure SetProportional(Value: Boolean);
    procedure DirectPaint(const ADestRect: TRect);
    procedure FindGraphicClass(Sender: TObject; const Context: TFindGraphicClassContext;
      var GraphicClass: TGraphicClass);
    function DestRect: TRect;
  strict protected
    function CanObserve(const ID: Integer): Boolean; override;
    function CanAutoSize(var NewWidth, NewHeight: Integer): Boolean; override;
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
  published
    property Align;
    property Anchors;
    property AutoSize;
    property Center: Boolean read FCenter write SetCenter default False;
    property Constraints;
    property DragCursor;
    property DragKind;
    property DragMode;
    property Enabled;
    property ParentShowHint;
    property Picture: TWICPicture read FPicture write SetPicture;
    property PopupMenu;
    property Proportional: Boolean read FProportional write SetProportional default false;
    property ShowHint;
    property Stretch: Boolean read FStretch write SetStretch default False;
    property Touch;
    property Visible;
    property OnClick;
    property OnContextPopup;
    property OnDblClick;
    property OnDragDrop;
    property OnDragOver;
    property OnEndDock;
    property OnEndDrag;
    property OnGesture;
    property OnMouseActivate;
    property OnMouseDown;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseMove;
    property OnMouseUp;
    property OnStartDock;
    property OnStartDrag;
  end;

procedure Register;

implementation

uses
  Winapi.D2D1, Winapi.Wincodec, Winapi.Messages,
  System.SysUtils, System.Math,
  Vcl.Consts, Vcl.Direct2D, Vcl.Forms;

procedure TWICPicture.FindGraphicClass(const Context: TFindGraphicClassContext;
  var GraphicClass: TGraphicClass);
begin
  GraphicClass := TWICImage;
end;

procedure TWICPicture.Assign(Source: TPersistent);
var
  S: TStream;
  G: TGraphic;
begin
  if Source = nil then
  begin
    Graphic := nil;
  end
  else if Source is TWicPicture then
  begin
    Graphic := TWicPicture(Source).Graphic;
  end
  else if Source is TPicture then
  begin
    if TPicture(Source).Graphic = nil then
    begin
      Graphic := nil;
    end
    else
    if TPicture(Source).Graphic is TWicImage then
    begin
      Graphic := TPicture(Source).Graphic;
    end
    else
    begin
      S := TMemoryStream.Create;
      try
        TPicture(Source).Graphic.SaveToStream(S);
        S.Seek(0, TSeekOrigin.soBeginning);
        G := TWicImage.Create;
        try
          G.LoadFromStream(S);
          Graphic := G;
        finally
          G.Free;
        end;
      finally
        S.Free;
      end;
    end;
  end
  else if Source is TWicImage then
    Graphic := TWicImage(Source)
  else
    inherited Assign(Source);
end;

constructor TDirect2DImage.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csReplicatable, csPannable];
  FPicture := TWicPicture.Create;
  FPicture.OnChange := PictureChanged;
  FPicture.OnFindGraphicClass := FindGraphicClass;
  Height := 105;
  Width := 105;
end;

destructor TDirect2DImage.Destroy;
begin
  FPicture.Free;
  inherited Destroy;
end;

function TDirect2DImage.CanObserve(const ID: Integer): Boolean;
begin
  Result := False;
  if ID = TObserverMapping.EditLinkID then
    Result := True;
end;

function TDirect2DImage.DestRect: TRect;
var
  w, h, cw, ch: Integer;
  xyaspect: Double;
begin
  w := Picture.Width;
  h := Picture.Height;
  cw := ClientWidth;
  ch := ClientHeight;
  if Stretch or (Proportional and ((w > cw) or (h > ch))) then
  begin
    if Proportional and (w > 0) and (h > 0) then
    begin
      xyaspect := w / h;
      if w > h then
      begin
        w := cw;
        h := Trunc(cw / xyaspect);
        if h > ch then  // woops, too big
        begin
          h := ch;
          w := Trunc(ch * xyaspect);
        end;
      end
      else
      begin
        h := ch;
        w := Trunc(ch * xyaspect);
        if w > cw then  // woops, too big
        begin
          w := cw;
          h := Trunc(cw / xyaspect);
        end;
      end;
    end
    else
    begin
      w := cw;
      h := ch;
    end;
  end;

  Result := TRect.Create(0, 0, w, h);

  if Center then
  begin
    OffsetRect(Result, (cw - w) div 2, (ch - h) div 2);
  end;
end;

procedure WicCheck(AHResult: HRESULT);
begin
  if Failed(AHResult) then
  begin
    raise EInvalidGraphic.Create(SInvalidImage + ': ' + SysErrorMessage(AHResult));
  end;
end;

procedure TDirect2DImage.DirectPaint(const ADestRect: TRect);
var
  DirectCanvas: TDirect2DCanvas;
  DirectBitmap: ID2D1Bitmap;
  RenderTarget: ID2D1RenderTarget;
  DestRect: TD2D1RectF;
  WicImage: TWicImage;
  ImagingFactory: IWicImagingFactory;
  BitmapScaler: IWICBitmapScaler;
  FormatConverter: IWicFormatConverter;
begin
  DirectCanvas := TDirect2DCanvas.Create(Canvas.Handle, ADestRect);
  try
    RenderTarget := DirectCanvas.RenderTarget;

    WicImage := FPicture.Graphic as TWicImage;

    ImagingFactory := WicImage.ImagingFactory;

    WicCheck(ImagingFactory.CreateBitmapScaler(BitmapScaler));

    WicCheck(BitmapScaler.Initialize(WicImage.Handle, ADestRect.Width, ADestRect.Height,
      WICBitmapInterpolationModeFant));

    WicCheck(ImagingFactory.CreateFormatConverter(FormatConverter));

    WicCheck(FormatConverter.Initialize(BitmapScaler, GUID_WICPixelFormat32bppPBGRA,
      WICBitmapDitherTypeNone, nil, 0, WICBitmapPaletteTypeCustom));

    WicCheck(RenderTarget.CreateBitmapFromWicBitmap(FormatConverter, nil, DirectBitmap));

    RenderTarget.BeginDraw();
    DestRect := ADestRect;
    RenderTarget.DrawBitmap(DirectBitmap, @DestRect);
    RenderTarget.EndDraw();
  finally
    DirectCanvas.Free;
  end;
end;

procedure TDirect2DImage.Paint;
var
  Save: Boolean;
begin
  if csDesigning in ComponentState then
  begin
    Canvas.Pen.Style := psDash;
    Canvas.Brush.Style := bsClear;
    Canvas.Rectangle(0, 0, Width, Height);
  end;
  Save := FDrawing;
  FDrawing := True;
  try
    if Assigned(Picture.Graphic) then
    begin
      DirectPaint(DestRect);
    end;
  finally
    FDrawing := Save;
  end;
end;

procedure TDirect2DImage.FindGraphicClass(Sender: TObject;
  const Context: TFindGraphicClassContext; var GraphicClass: TGraphicClass);
begin
  GraphicClass := TWICImage;
end;

procedure TDirect2DImage.SetCenter(Value: Boolean);
begin
  if FCenter <> Value then
  begin
    FCenter := Value;
    PictureChanged(Self);
  end;
end;

procedure TDirect2DImage.SetPicture(Value: TWicPicture);
begin
  FPicture.Assign(Value);
end;

procedure TDirect2DImage.SetStretch(Value: Boolean);
begin
  if Value <> FStretch then
  begin
    FStretch := Value;
    PictureChanged(Self);
  end;
end;

procedure TDirect2DImage.SetProportional(Value: Boolean);
begin
  if FProportional <> Value then
  begin
    FProportional := Value;
    PictureChanged(Self);
  end;
end;

procedure TDirect2DImage.PictureChanged(Sender: TObject);
var
  G: TGraphic;
  D: TRect;
begin
  if Observers.IsObserving(TObserverMapping.EditLinkID) then
    if TLinkObservers.EditLinkEdit(Observers) then
      TLinkObservers.EditLinkModified(Observers);

  if AutoSize and (Picture.Width > 0) and (Picture.Height > 0) then
  	SetBounds(Left, Top, Picture.Width, Picture.Height);

  G := Picture.Graphic;
  if G <> nil then
  begin
    D := DestRect;
    if (D.Left <= 0) and (D.Top <= 0) and
       (D.Right >= Width) and (D.Bottom >= Height) then
      ControlStyle := ControlStyle + [csOpaque]
    else  // picture might not cover entire clientrect
      ControlStyle := ControlStyle - [csOpaque];
  end
  else
    ControlStyle := ControlStyle - [csOpaque];

  if not FDrawing then Invalidate;

  if Observers.IsObserving(TObserverMapping.EditLinkID) then
    if TLinkObservers.EditLinkIsEditing(Observers) then
      TLinkObservers.EditLinkUpdate(Observers);
end;

function TDirect2DImage.CanAutoSize(var NewWidth, NewHeight: Integer): Boolean;
begin
  Result := True;
  if not (csDesigning in ComponentState) or (Picture.Width > 0) and
    (Picture.Height > 0) then
  begin
    if Align in [alNone, alLeft, alRight] then
      NewWidth := Picture.Width;
    if Align in [alNone, alTop, alBottom] then
      NewHeight := Picture.Height;
  end;
end;

procedure Register;
begin
  RegisterComponents('Direct2DImage', [TDirect2DImage]);
end;

end.

