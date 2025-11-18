// Treasury.mo - Handles ckBTC payments, fee collection, withdrawals
import Principal "mo:base/Principal";
import Nat "mo:base/Nat";
import Nat64 "mo:base/Nat64";
import Int "mo:base/Int";
import Time "mo:base/Time";
import HashMap "mo:base/HashMap";
import Iter "mo:base/Iter";
import Blob "mo:base/Blob";
import Array "mo:base/Array";
import Text "mo:base/Text";
import Types "Types";

actor class Treasury(initArgs: { registryCanister: Principal; admin: Principal }) {
  type Error = Types.Error;
  type Result<T, E> = Types.Result<T, E>;
  type Account = Types.Account;

  // ===== CONFIGURATION =====
  
  // ckBTC Ledger canister on mainnet
  let CKBTC_LEDGER: Principal = Principal.fromText("mxzaz-hqaaa-aaaar-qaada-cai");
  let CKBTC_FEE: Nat = 10; // 10 satoshis
  
  // Platform fee: 2% (200 basis points)
  stable var platformFeeBps: Nat = 200;
  stable var admin: Principal = initArgs.admin;
  stable var registryCanister: Principal = initArgs.registryCanister;
  
  // Balances: creator principal -> available balance
  stable var balancesEntries: [(Principal, Nat)] = [];
  var balances = HashMap.HashMap<Principal, Nat>(10, Principal.equal, Principal.hash);
  
  // Platform collected fees
  stable var totalFeesCollected: Nat = 0;
  stable var availableFees: Nat = 0;

  // ===== ICRC-1 INTERFACE =====
  
  let ckbtcLedger = actor(Principal.toText(CKBTC_LEDGER)): actor {
    icrc1_balance_of: shared query Account -> async Nat;
    icrc1_transfer: shared Types.TransferArgs -> async Types.TransferResult;
    icrc2_transfer_from: shared {
      from: Account;
      to: Account;
      amount: Nat;
      fee: ?Nat;
      memo: ?Blob;
      created_at_time: ?Nat64;
      spender_subaccount: ?Blob;
    } -> async Types.TransferResult;
  };

  // Registry interface
  let registry = actor(Principal.toText(registryCanister)): actor {
    getTipJar: shared query Types.TipJarId -> async Result<Types.TipJar, Error>;
    recordTipReceived: shared (Types.TipJarId, Nat) -> async Result<(), Error>;
  };

  // ===== SUBACCOUNT HELPERS =====
  
  // Generate unique subaccount for each user's deposits
  func principalToSubaccount(p: Principal): Blob {
    let bytes = Blob.toArray(Principal.toBlob(p));
    let subaccount = Array.tabulate<Nat8>(32, func(i) {
      if (i < bytes.size()) { bytes[i] } else { 0 }
    });
    Blob.fromArray(subaccount)
  };

  // Get deposit address for a user
  public query func getDepositAccount(user: Principal): async Account {
    {
      owner = Principal.fromActor(Treasury);
      subaccount = ?principalToSubaccount(user);
    }
  };

  // ===== TIP PROCESSING =====

  // Send a tip - user must have approved this canister via icrc2_approve first
  public shared(msg) func sendTip(req: Types.SendTipRequest): async Result<Types.Tip, Error> {
    let tipper = msg.caller;
    
    // Validate tip jar exists and is active
    let jarResult = await registry.getTipJar(req.tipJarId);
    let jar = switch (jarResult) {
      case (#err(e)) { return #err(e) };
      case (#ok(j)) {
        if (not j.isActive) {
          return #err(#invalidInput("Tip jar is not active"));
        };
        j
      };
    };

    // Calculate fees
    let grossAmount = req.amount;
    let platformFee = (grossAmount * platformFeeBps) / 10000;
    let netAmount = grossAmount - platformFee - CKBTC_FEE;

    if (netAmount == 0) {
      return #err(#invalidInput("Amount too small after fees"));
    };

    // Transfer from tipper to this canister using ICRC-2
    let transferFromResult = await ckbtcLedger.icrc2_transfer_from({
      from = { owner = tipper; subaccount = null };
      to = { owner = Principal.fromActor(Treasury); subaccount = null };
      amount = grossAmount;
      fee = ?CKBTC_FEE;
      memo = ?Text.encodeUtf8(req.tipJarId);
      created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
      spender_subaccount = null;
    });

    let txId = switch (transferFromResult) {
      case (#Err(e)) {
        return #err(#transferFailed(debug_show(e)));
      };
      case (#Ok(idx)) { idx };
    };

    // Credit creator's balance
    let currentBalance = switch (balances.get(jar.owner)) {
      case null { 0 };
      case (?b) { b };
    };
    balances.put(jar.owner, currentBalance + netAmount);

    // Track platform fees
    totalFeesCollected += platformFee;
    availableFees += platformFee;

    // Update registry stats
    ignore await registry.recordTipReceived(req.tipJarId, netAmount);

    let tip: Types.Tip = {
      id = "tip_" # Nat.toText(txId);
      tipJarId = req.tipJarId;
      from = tipper;
      to = jar.owner;
      grossAmount = grossAmount;
      fee = platformFee;
      netAmount = netAmount;
      message = req.message;
      timestamp = Time.now();
      txId = ?txId;
      status = #completed;
    };

    #ok(tip)
  };

  // ===== WITHDRAWALS =====

  // Creator withdraws their balance to their own wallet
  public shared(msg) func withdraw(amount: Nat, toAccount: Account): async Result<Nat, Error> {
    let caller = msg.caller;
    
    let balance = switch (balances.get(caller)) {
      case null { return #err(#insufficientFunds) };
      case (?b) { b };
    };

    if (amount > balance) {
      return #err(#insufficientFunds);
    };

    // Deduct from balance first (optimistic)
    balances.put(caller, balance - amount);

    // Transfer ckBTC to user's wallet
    let transferResult = await ckbtcLedger.icrc1_transfer({
      from_subaccount = null;
      to = toAccount;
      amount = amount - CKBTC_FEE; // User pays transfer fee
      fee = ?CKBTC_FEE;
      memo = null;
      created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
    });

    switch (transferResult) {
      case (#Err(e)) {
        // Rollback balance
        balances.put(caller, balance);
        #err(#transferFailed(debug_show(e)))
      };
      case (#Ok(txId)) {
        #ok(txId)
      };
    }
  };

  // Get user's available balance
  public query func getBalance(user: Principal): async Nat {
    switch (balances.get(user)) {
      case null { 0 };
      case (?b) { b };
    }
  };

  // ===== ADMIN FUNCTIONS =====

  public shared(msg) func withdrawFees(toAccount: Account): async Result<Nat, Error> {
    if (msg.caller != admin) {
      return #err(#unauthorized);
    };

    if (availableFees == 0) {
      return #err(#insufficientFunds);
    };

    let amount = availableFees;
    availableFees := 0;

    let transferResult = await ckbtcLedger.icrc1_transfer({
      from_subaccount = null;
      to = toAccount;
      amount = amount - CKBTC_FEE;
      fee = ?CKBTC_FEE;
      memo = ?Text.encodeUtf8("platform_fees");
      created_at_time = ?Nat64.fromNat(Int.abs(Time.now()));
    });

    switch (transferResult) {
      case (#Err(e)) {
        availableFees := amount; // Rollback
        #err(#transferFailed(debug_show(e)))
      };
      case (#Ok(txId)) {
        #ok(txId)
      };
    }
  };

  public shared(msg) func setFee(newFeeBps: Nat): async Result<(), Error> {
    if (msg.caller != admin) {
      return #err(#unauthorized);
    };
    if (newFeeBps > 1000) { // Max 10%
      return #err(#invalidInput("Fee too high"));
    };
    platformFeeBps := newFeeBps;
    #ok(())
  };

  public shared(msg) func setAdmin(newAdmin: Principal): async Result<(), Error> {
    if (msg.caller != admin) {
      return #err(#unauthorized);
    };
    admin := newAdmin;
    #ok(())
  };

  // ===== STATS =====

  public query func getStats(): async {
    totalFeesCollected: Nat;
    availableFees: Nat;
    platformFeeBps: Nat;
  } {
    {
      totalFeesCollected = totalFeesCollected;
      availableFees = availableFees;
      platformFeeBps = platformFeeBps;
    }
  };

  public query func getCanisterBalance(): async Nat {
    // This would need to be called async in practice
    0 // Placeholder - actual balance check is async
  };

  // ===== UPGRADE HOOKS =====

  system func preupgrade() {
    balancesEntries := Iter.toArray(balances.entries());
  };

  system func postupgrade() {
    balances := HashMap.fromIter<Principal, Nat>(balancesEntries.vals(), 10, Principal.equal, Principal.hash);
  };
}