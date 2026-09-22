///|
/// A minimal local example for the currently implemented in-memory API.
fn main {
  let database = @moonpropertydb.Database::new_in_memory()
  let transaction = try! database.begin_write()
  let package_a = try! transaction.create_node(["Package"], {
    "name": @moonpropertydb.PropertyValue::String("app"),
  })
  let package_b = try! transaction.create_node(["Package"], {
    "name": @moonpropertydb.PropertyValue::String("core"),
  })
  let _dependency = try! transaction.create_edge(
    package_a,
    package_b,
    "DEPENDS_ON",
    {},
  )
  try! transaction.commit()
  let committed = try! database.get_node(package_a)
  println("committed package labels: \{committed.labels.length()}")
  try! database.close()
}
