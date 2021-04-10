object FormLogistics: TFormLogistics
  Left = 0
  Top = 0
  Caption = 'FormLogistics'
  ClientHeight = 826
  ClientWidth = 870
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -11
  Font.Name = 'Tahoma'
  Font.Style = []
  OldCreateOrder = False
  OnCreate = FormCreate
  OnShow = FormShow
  PixelsPerInch = 96
  TextHeight = 13
  object vstPageCtrl: TPageControl
    Left = 0
    Top = 105
    Width = 870
    Height = 721
    ActivePage = tabSheetDeliveries
    Align = alClient
    TabOrder = 0
    OnChange = vstPageCtrlChange
    ExplicitTop = 143
    ExplicitWidth = 707
    ExplicitHeight = 681
    object tabSheetDeliveries: TTabSheet
      Caption = 'Deliveries'
      ExplicitLeft = 8
    end
    object tabSheetOffers: TTabSheet
      Caption = 'Offers'
      ImageIndex = 1
      ExplicitWidth = 691
      ExplicitHeight = 395
    end
    object tabSheetDemands: TTabSheet
      Caption = 'Demands'
      ImageIndex = 2
      ExplicitWidth = 691
      ExplicitHeight = 395
    end
  end
  object gbFilter: TGroupBox
    Left = 0
    Top = 0
    Width = 870
    Height = 105
    Align = alTop
    Caption = 'Filter'
    TabOrder = 1
    object Label1: TLabel
      Left = 10
      Top = 16
      Width = 30
      Height = 13
      Caption = 'Hands'
    end
    object clbHandsFilter: TCheckListBox
      Left = 10
      Top = 35
      Width = 191
      Height = 62
      OnClickCheck = FilterUpdated
      Columns = 6
      CheckBoxPadding = 2
      ItemHeight = 15
      Items.Strings = (
        '0'
        '1'
        '2'
        '3'
        '4'
        '5'
        '6'
        '7'
        '8'
        '9'
        '10'
        '11'
        '12'
        '13'
        '14'
        '15'
        '16'
        '17')
      TabOrder = 0
    end
    object gbToFromID: TGroupBox
      Left = 216
      Top = 18
      Width = 177
      Height = 81
      Caption = 'To / From ID'
      TabOrder = 1
      object seToID: TSpinEdit
        Left = 68
        Top = 19
        Width = 97
        Height = 22
        MaxValue = 2147483647
        MinValue = 0
        TabOrder = 0
        Value = 0
        OnChange = FilterUpdated
      end
      object seFromID: TSpinEdit
        Left = 68
        Top = 47
        Width = 97
        Height = 22
        MaxValue = 2147483647
        MinValue = 0
        TabOrder = 1
        Value = 0
        OnChange = FilterUpdated
      end
      object cbToID: TCheckBox
        Left = 8
        Top = 21
        Width = 49
        Height = 17
        Caption = 'To ID'
        TabOrder = 2
        OnClick = FilterUpdated
      end
      object cbFromID: TCheckBox
        Left = 8
        Top = 44
        Width = 54
        Height = 17
        Caption = 'From ID'
        TabOrder = 3
        OnClick = FilterUpdated
      end
    end
    object btnUncheckAll: TButton
      Left = 127
      Top = 15
      Width = 74
      Height = 18
      Caption = 'Uncheck all'
      TabOrder = 2
      OnClick = btnUncheckAllClick
    end
    object btnCheckAll: TButton
      Left = 65
      Top = 15
      Width = 56
      Height = 18
      Caption = 'Check all'
      TabOrder = 3
      OnClick = btnCheckAllClick
    end
  end
end
