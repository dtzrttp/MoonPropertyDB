// Blackbox tests run against the package's public API. Use `@moonpropertydb` to import.
// Prefer high-level behaviors over implementation details.
// Run `moon test` to execute and `moon test --update` to refresh snapshots.

///|
test "scalar property values retain their type and payload" {
  assert_eq(
    @moonpropertydb.PropertyValue::Bool(true),
    @moonpropertydb.PropertyValue::Bool(true),
  )
  assert_not_eq(
    @moonpropertydb.PropertyValue::Bool(true),
    @moonpropertydb.PropertyValue::Bool(false),
  )
  assert_eq(
    @moonpropertydb.PropertyValue::Int64(1),
    @moonpropertydb.PropertyValue::Int64(1),
  )
  assert_not_eq(
    @moonpropertydb.PropertyValue::Int64(1),
    @moonpropertydb.PropertyValue::Float64(1.0),
  )
  assert_eq(
    @moonpropertydb.PropertyValue::String("Alice"),
    @moonpropertydb.PropertyValue::String("Alice"),
  )
  assert_eq(
    @moonpropertydb.PropertyValue::Bytes(b"graph"),
    @moonpropertydb.PropertyValue::Bytes(b"graph"),
  )
}
