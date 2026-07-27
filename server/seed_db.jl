using Skein
db = SkeinDB("../data/knots.db")
n = Skein.import_knotinfo!(db)
println("Imported $n knots")
close(db)
