// History.mo - Stores tip history and provides analytics
import HashMap "mo:base/HashMap";
import Principal "mo:base/Principal";
import Text "mo:base/Text";
import Time "mo:base/Time";
import Array "mo:base/Array";
import Iter "mo:base/Iter";
import Buffer "mo:base/Buffer";
import Nat "mo:base/Nat";
import Int "mo:base/Int";
import Order "mo:base/Order";
import Types "Types";

actor class History(initArgs: { treasuryCanister: Principal }) {
  type Tip = Types.Tip;
  type TipJarId = Types.TipJarId;
  type Error = Types.Error;
  type Result<T, E> = Types.Result<T, E>;

  stable var treasuryCanister: Principal = initArgs.treasuryCanister;
  
  // Stable storage
  stable var tipsEntries: [(Text, Tip)] = [];
  stable var tipCounter: Nat = 0;
  
  // Runtime indexes
  var tips = HashMap.HashMap<Text, Tip>(100, Text.equal, Text.hash);
  var tipsByJar = HashMap.HashMap<TipJarId, Buffer.Buffer<Text>>(10, Text.equal, Text.hash);
  var tipsByTipper = HashMap.HashMap<Principal, Buffer.Buffer<Text>>(10, Principal.equal, Principal.hash);
  var tipsByCreator = HashMap.HashMap<Principal, Buffer.Buffer<Text>>(10, Principal.equal, Principal.hash);

  // ===== TIP RECORDING =====

  // Called by Treasury after successful tip
  public shared(msg) func recordTip(tip: Tip): async Result<Text, Error> {
    // TODO: Verify caller is Treasury canister
    // if (msg.caller != treasuryCanister) {
    //   return #err(#unauthorized);
    // };

    tips.put(tip.id, tip);

    // Index by jar
    switch (tipsByJar.get(tip.tipJarId)) {
      case null {
        let buf = Buffer.Buffer<Text>(10);
        buf.add(tip.id);
        tipsByJar.put(tip.tipJarId, buf);
      };
      case (?buf) {
        buf.add(tip.id);
      };
    };

    // Index by tipper
    switch (tipsByTipper.get(tip.from)) {
      case null {
        let buf = Buffer.Buffer<Text>(10);
        buf.add(tip.id);
        tipsByTipper.put(tip.from, buf);
      };
      case (?buf) {
        buf.add(tip.id);
      };
    };

    // Index by creator
    switch (tipsByCreator.get(tip.to)) {
      case null {
        let buf = Buffer.Buffer<Text>(10);
        buf.add(tip.id);
        tipsByCreator.put(tip.to, buf);
      };
      case (?buf) {
        buf.add(tip.id);
      };
    };

    #ok(tip.id)
  };

  // ===== QUERIES =====

  public query func getTip(tipId: Text): async Result<Tip, Error> {
    switch (tips.get(tipId)) {
      case null { #err(#notFound) };
      case (?t) { #ok(t) };
    }
  };

  public query func getTipsByJar(jarId: TipJarId, limit: Nat, offset: Nat): async [Tip] {
    switch (tipsByJar.get(jarId)) {
      case null { [] };
      case (?buf) {
        let all = Buffer.toArray(buf);
        let sorted = Array.sort<Text>(all, func(a, b) {
          // Sort by tip ID descending (newest first)
          Text.compare(b, a)
        });
        paginateAndFetch(sorted, limit, offset)
      };
    }
  };

  public query func getTipsByTipper(tipper: Principal, limit: Nat, offset: Nat): async [Tip] {
    switch (tipsByTipper.get(tipper)) {
      case null { [] };
      case (?buf) {
        let all = Buffer.toArray(buf);
        let sorted = Array.sort<Text>(all, func(a, b) { Text.compare(b, a) });
        paginateAndFetch(sorted, limit, offset)
      };
    }
  };

  public query func getTipsByCreator(creator: Principal, limit: Nat, offset: Nat): async [Tip] {
    switch (tipsByCreator.get(creator)) {
      case null { [] };
      case (?buf) {
        let all = Buffer.toArray(buf);
        let sorted = Array.sort<Text>(all, func(a, b) { Text.compare(b, a) });
        paginateAndFetch(sorted, limit, offset)
      };
    }
  };

  func paginateAndFetch(tipIds: [Text], limit: Nat, offset: Nat): [Tip] {
    let result = Buffer.Buffer<Tip>(limit);
    var i = offset;
    while (i < tipIds.size() and result.size() < limit) {
      switch (tips.get(tipIds[i])) {
        case (?tip) { result.add(tip) };
        case null {};
      };
      i += 1;
    };
    Buffer.toArray(result)
  };

  // ===== ANALYTICS =====

  public query func getJarStats(jarId: TipJarId): async {
    totalTips: Nat;
    totalAmount: Nat;
    uniqueTippers: Nat;
    averageTip: Nat;
  } {
    switch (tipsByJar.get(jarId)) {
      case null {
        { totalTips = 0; totalAmount = 0; uniqueTippers = 0; averageTip = 0 }
      };
      case (?buf) {
        let tipIds = Buffer.toArray(buf);
        var totalAmount: Nat = 0;
        let tippers = HashMap.HashMap<Principal, Bool>(10, Principal.equal, Principal.hash);
        
        for (tipId in tipIds.vals()) {
          switch (tips.get(tipId)) {
            case (?tip) {
              totalAmount += tip.netAmount;
              tippers.put(tip.from, true);
            };
            case null {};
          };
        };

        let totalTips = tipIds.size();
        let uniqueTippers = tippers.size();
        let averageTip = if (totalTips > 0) { totalAmount / totalTips } else { 0 };

        { totalTips; totalAmount; uniqueTippers; averageTip }
      };
    }
  };

  public query func getCreatorStats(creator: Principal): async {
    totalTips: Nat;
    totalReceived: Nat;
    uniqueTippers: Nat;
    topTippers: [(Principal, Nat)];
  } {
    switch (tipsByCreator.get(creator)) {
      case null {
        { totalTips = 0; totalReceived = 0; uniqueTippers = 0; topTippers = [] }
      };
      case (?buf) {
        let tipIds = Buffer.toArray(buf);
        var totalReceived: Nat = 0;
        let tipperAmounts = HashMap.HashMap<Principal, Nat>(10, Principal.equal, Principal.hash);
        
        for (tipId in tipIds.vals()) {
          switch (tips.get(tipId)) {
            case (?tip) {
              totalReceived += tip.netAmount;
              let current = switch (tipperAmounts.get(tip.from)) {
                case null { 0 };
                case (?a) { a };
              };
              tipperAmounts.put(tip.from, current + tip.netAmount);
            };
            case null {};
          };
        };

        // Get top 5 tippers
        let tippersArray = Iter.toArray(tipperAmounts.entries());
        let sorted = Array.sort<(Principal, Nat)>(tippersArray, func(a, b) {
          Nat.compare(b.1, a.1) // Descending by amount
        });
        let topTippers = if (sorted.size() > 5) {
          Array.tabulate<(Principal, Nat)>(5, func(i) { sorted[i] })
        } else {
          sorted
        };

        {
          totalTips = tipIds.size();
          totalReceived;
          uniqueTippers = tipperAmounts.size();
          topTippers;
        }
      };
    }
  };

  public query func getRecentTips(limit: Nat): async [Tip] {
    let allTips = Iter.toArray(tips.vals());
    let sorted = Array.sort<Tip>(allTips, func(a, b) {
      Int.compare(b.timestamp, a.timestamp)
    });
    
    if (sorted.size() > limit) {
      Array.tabulate<Tip>(limit, func(i) { sorted[i] })
    } else {
      sorted
    }
  };

  public query func getGlobalStats(): async {
    totalTips: Nat;
    totalVolume: Nat;
    uniqueTippers: Nat;
    uniqueCreators: Nat;
  } {
    var totalVolume: Nat = 0;
    for (tip in tips.vals()) {
      totalVolume += tip.netAmount;
    };

    {
      totalTips = tips.size();
      totalVolume;
      uniqueTippers = tipsByTipper.size();
      uniqueCreators = tipsByCreator.size();
    }
  };

  // ===== UPGRADE HOOKS =====

  system func preupgrade() {
    tipsEntries := Iter.toArray(tips.entries());
  };

  system func postupgrade() {
    tips := HashMap.fromIter<Text, Tip>(tipsEntries.vals(), 100, Text.equal, Text.hash);
    
    // Rebuild indexes
    tipsByJar := HashMap.HashMap<TipJarId, Buffer.Buffer<Text>>(10, Text.equal, Text.hash);
    tipsByTipper := HashMap.HashMap<Principal, Buffer.Buffer<Text>>(10, Principal.equal, Principal.hash);
    tipsByCreator := HashMap.HashMap<Principal, Buffer.Buffer<Text>>(10, Principal.equal, Principal.hash);
    
    for ((tipId, tip) in tips.entries()) {
      // Index by jar
      switch (tipsByJar.get(tip.tipJarId)) {
        case null {
          let buf = Buffer.Buffer<Text>(10);
          buf.add(tipId);
          tipsByJar.put(tip.tipJarId, buf);
        };
        case (?buf) { buf.add(tipId) };
      };

      // Index by tipper
      switch (tipsByTipper.get(tip.from)) {
        case null {
          let buf = Buffer.Buffer<Text>(10);
          buf.add(tipId);
          tipsByTipper.put(tip.from, buf);
        };
        case (?buf) { buf.add(tipId) };
      };

      // Index by creator
      switch (tipsByCreator.get(tip.to)) {
        case null {
          let buf = Buffer.Buffer<Text>(10);
          buf.add(tipId);
          tipsByCreator.put(tip.to, buf);
        };
        case (?buf) { buf.add(tipId) };
      };
    };
  };
}