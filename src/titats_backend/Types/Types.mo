// Types.mo - Shared types for Titats tip jar platform

module {
  // Basic types
  public type Principal = Principal;
  public type Timestamp = Int;
  public type TipJarId = Text;
  
  // Creator profile
  public type Creator = {
    id: Principal;
    username: Text;
    displayName: Text;
    bio: Text;
    avatarUrl: Text;
    createdAt: Timestamp;
    totalReceived: Nat;
    tipJarIds: [TipJarId];
  };

  public type CreateCreatorRequest = {
    username: Text;
    displayName: Text;
    bio: Text;
    avatarUrl: Text;
  };

  // Tip jar configuration
  public type TipJar = {
    id: TipJarId;
    owner: Principal;
    name: Text;
    description: Text;
    targetAmount: ?Nat; // Optional goal
    currentAmount: Nat;
    suggestedAmounts: [Nat]; // In satoshis
    thankYouMessage: Text;
    isActive: Bool;
    createdAt: Timestamp;
    widgetTheme: WidgetTheme;
  };

  public type CreateTipJarRequest = {
    name: Text;
    description: Text;
    targetAmount: ?Nat;
    suggestedAmounts: [Nat];
    thankYouMessage: Text;
    widgetTheme: WidgetTheme;
  };

  public type WidgetTheme = {
    primaryColor: Text;
    backgroundColor: Text;
    textColor: Text;
    borderRadius: Nat;
  };

  // Tip transaction
  public type Tip = {
    id: Text;
    tipJarId: TipJarId;
    from: Principal;
    to: Principal;
    grossAmount: Nat;
    fee: Nat;
    netAmount: Nat;
    message: ?Text;
    timestamp: Timestamp;
    txId: ?Nat; // ckBTC ledger tx index
    status: TipStatus;
  };

  public type TipStatus = {
    #pending;
    #completed;
    #failed: Text;
  };

  public type SendTipRequest = {
    tipJarId: TipJarId;
    amount: Nat;
    message: ?Text;
  };

  // Platform stats
  public type PlatformStats = {
    totalCreators: Nat;
    totalTipJars: Nat;
    totalTips: Nat;
    totalVolume: Nat;
    totalFeesCollected: Nat;
  };

  // ICRC-1 types for ckBTC interaction
  public type Account = {
    owner: Principal;
    subaccount: ?Blob;
  };

  public type TransferArgs = {
    from_subaccount: ?Blob;
    to: Account;
    amount: Nat;
    fee: ?Nat;
    memo: ?Blob;
    created_at_time: ?Nat64;
  };

  public type TransferResult = {
    #Ok: Nat;
    #Err: TransferError;
  };

  public type TransferError = {
    #BadFee: { expected_fee: Nat };
    #BadBurn: { min_burn_amount: Nat };
    #InsufficientFunds: { balance: Nat };
    #TooOld;
    #CreatedInFuture: { ledger_time: Nat64 };
    #Duplicate: { duplicate_of: Nat };
    #TemporarilyUnavailable;
    #GenericError: { error_code: Nat; message: Text };
  };

  // Result types
  public type Result<T, E> = {
    #ok: T;
    #err: E;
  };

  public type Error = {
    #notFound;
    #alreadyExists;
    #unauthorized;
    #invalidInput: Text;
    #transferFailed: Text;
    #insufficientFunds;
    #systemError: Text;
  };
}