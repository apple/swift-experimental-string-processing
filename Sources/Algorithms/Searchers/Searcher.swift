public struct DefaultSearcherState<Searched: Collection> {
  enum _State {
    case index(Searched.Index)
    case done
  }
  
  let state: _State
}

public protocol CollectionSearcher {
  associatedtype Searched: Collection where Searched.SubSequence == Searched
  associatedtype State
  
  func state(for searched: Searched, startingAt index: Searched.Index) -> State
  func search(_ searched: Searched, _ state: inout State) -> Range<Searched.Index>?
}

public protocol StatelessCollectionSearcher: CollectionSearcher
  where State == DefaultSearcherState<Searched>
{
  func search(_ searched: Searched, from index: Searched.Index) -> Range<Searched.Index>?
}

extension StatelessCollectionSearcher {
  public func state(for searched: Searched, startingAt index: Searched.Index) -> State {
    State(state: .index(index))
  }
  
  public func search(_ searched: Searched, _ state: inout State) -> Range<Searched.Index>? {
    guard
      case .index(let index) = state.state,
      let range = search(searched, from: index)
    else { return nil }
    
    
    if range.isEmpty {
      if range.upperBound == searched.endIndex {
        state = State(state: .done)
      } else {
        state = State(state: .index(searched.index(after: range.upperBound)))
      }
    } else {
      state = State(state: .index(range.upperBound))
    }
    
    return range
  }
}

// MARK: Searching from the back

// TODO: Decide whether or not to inherit from `CollectionSearcher`
public protocol BackwardCollectionSearcher: CollectionSearcher where Searched: BidirectionalCollection {
  associatedtype BackwardState
  
  func backwardState(for searched: Searched) -> BackwardState
  func searchBack(_ searched: Searched, _ state: inout BackwardState) -> Range<Searched.Index>?
}

public protocol StatelessBackwardCollectionSearcher: BackwardCollectionSearcher
  where BackwardState == DefaultSearcherState<Searched>
{
  func searchBack(_ searched: Searched, from index: Searched.Index) -> Range<Searched.Index>?
}

extension StatelessBackwardCollectionSearcher {
  public func backwardState(for searched: Searched) -> BackwardState {
    BackwardState(state: .index(searched.endIndex))
  }
  
  public func searchBack(_ searched: Searched, _ state: inout BackwardState) -> Range<Searched.Index>? {
    guard
      case .index(let index) = state.state,
      let range = searchBack(searched, from: index)
    else { return nil }
    
    
    if range.isEmpty {
      if range.lowerBound == searched.startIndex {
        state = BackwardState(state: .done)
      } else {
        state = BackwardState(state: .index(searched.index(before: range.lowerBound)))
      }
    } else {
      state = BackwardState(state: .index(range.lowerBound))
    }
    
    return range
  }
}

public protocol BidirectionalCollectionSearcher: BackwardCollectionSearcher {}
