import SwiftUI
import Combine
import ComposableArchitecture

struct AppReducer: ReducerProtocol {
  struct State: Equatable {
    // 1. Initialize empty state
    var recipes = IdentifiedArrayOf<DatabaseClient.Recipe>()
  }
  enum Action: Equatable {
    case task
    case taskResponse(TaskResult<[DatabaseClient.Recipe]>)
    case deleteButtonTapped(id: DatabaseClient.Recipe.ID)
  }
  
  @Dependency(\.database) var database
  
  var body: some ReducerProtocolOf<Self> {
    Reduce { state, action in
      switch action {
    
      case .task:
        // 2. Create  `run` effect to await AsyncStream of recipes emitted from dependency
        return .run { send in
          for await value in self.database.recipes() {
            await send(.taskResponse(.success(value)))
          }
        }
        
      case let .taskResponse(.success(value)):
        // 3. On success, update state with new value
        state.recipes = .init(uniqueElements: value)
        return .none
        
      case let .deleteButtonTapped(id: id):
        return .run { _ in
          try await self.database.deleteRecipe(id)
        }
        
      default:
        return .none
      }
    }
  }
}

// MARK: - Dependency

// 4. Create the Dependency interface

struct DatabaseClient {
   
  var recipes: @Sendable () -> AsyncStream<[Recipe]>
  var deleteRecipe: @Sendable (Recipe.ID) async throws -> Void
  
  struct Recipe: Identifiable, Equatable, Codable {
    let id: UUID
    var name: String
  }
}

extension DependencyValues {
  var database: DatabaseClient {
    get { self[DatabaseClient.self] }
    set { self[DatabaseClient.self] = newValue }
  }
}

extension DatabaseClient: DependencyKey {
  static var liveValue = Self.live
  //static var previewValue = Self.preview
  //static var testValue = Self.test
}


// 5. Create the live implementation

extension DatabaseClient {
  static var live: Self {
    
    // 6. create private actor inside static implementation
    final actor Actor {
      
      // 7. publish the state
      @Published var recipes = IdentifiedArrayOf<Recipe>(uniqueElements: [
        .init(id: UUID(), name: "Chicken Parmesan"),
        .init(id: UUID(), name: "Spaghetti Bolognese"),
        .init(id: UUID(), name: "Vegetable Stir-Fry"),
      ])
      
      func remove(recipe id: Recipe.ID) {
        self.recipes.remove(id: id)
      }
    }
    
    let actor = Actor()
    
    return Self(
      recipes: {
        // 8. open a stream which opens a task
        AsyncStream { continuation in
          let task = Task {
            while !Task.isCancelled {
              // 9. yield published values until task is cancelled
              for await value in await actor.$recipes.values {
                continuation.yield(value.elements)
              }
            }
          }
          continuation.onTermination = { _ in task.cancel() }
        }
      },
      deleteRecipe: { id in
        await actor.remove(recipe: id)
      }
    )
  }
}

// MARK: - SwiftUI

struct AppView: View {
  let store: StoreOf<AppReducer>
  
  var body: some View {
    WithViewStore(store) { viewStore in
      NavigationStack {
        List {
          Section("Results") {
            ForEach(viewStore.recipes) { recipe in
              Text(recipe.name)
            }
          }
        }
        .navigationTitle("Recipes")
        
        // 10. Create `task` tied to view lifecycle (automatically tears down effect on dissappear)
        .task { await viewStore.send(.task).finish() }
      }
    }
  }
}

// MARK: - SwiftUI Previews

struct AppView_Previews: PreviewProvider {
  static var previews: some View {
    AppView(store: Store(
      initialState: AppReducer.State(),
      reducer: AppReducer()
    ))
  }
}
