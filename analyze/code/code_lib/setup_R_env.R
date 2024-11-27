# 5_setup_R_env
# note: requires Rtools

# NOTE: run under R version 4.4.2

# Install devtools if not already installed
if (!requireNamespace("devtools", quietly = TRUE)) {
    install.packages("devtools")
}

# Install specific versions of packages using devtools
devtools::install_version("grf", version = "2.4.0")
devtools::install_version("data.table", version = "1.16.2")
devtools::install_version("lfe", version = "3.1.0")
devtools::install_version("gtools", version = "3.9.5")
devtools::install_version("fixest", version = "0.12.1")
devtools::install_version("RColorBrewer", version = "1.1-3")
devtools::install_version("ggplot2", version = "3.5.1")
devtools::install_version("readxl", version = "1.4.3")
devtools::install_version("akima", version = "0.6-3.4")
devtools::install_version("latex2exp", version = "0.9.6")
devtools::install_version("kdensity", version = "1.1.0")

# Verify installations
installed_packages <- installed.packages()
for(pkg in c("grf", "data.table", "lfe", "gtools", "fixest", 
             "RColorBrewer", "ggplot2", "readxl", "akima", 
             "latex2exp", "kdensity")) {
    cat(sprintf("Package: %s, Version: %s\n", 
                pkg, 
                installed_packages[pkg, "Version"]))
}
