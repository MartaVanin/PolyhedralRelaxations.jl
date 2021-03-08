"""
    function _build_mccormick_relaxation!(m, x, y, z)

McCormick relaxation of binlinear term 
```
z >= JuMP.lower_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.lower_bound(x)*JuMP.lower_bound(y)
z >= JuMP.upper_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.upper_bound(x)*JuMP.upper_bound(y)
z <= JuMP.lower_bound(x)*y + JuMP.upper_bound(y)*x - JuMP.lower_bound(x)*JuMP.upper_bound(y)
z <= JuMP.upper_bound(x)*y + JuMP.lower_bound(y)*x - JuMP.upper_bound(x)*JuMP.lower_bound(y)
```
"""
function _build_mccormick_relaxation!(m::JuMP.Model, x::JuMP.VariableRef, y::JuMP.VariableRef, z::JuMP.VariableRef)::FormulationInfo
    x_lb, x_ub = _variable_domain(x)
    y_lb, y_ub = _variable_domain(y)

    formulation_info = FormulationInfo()

    formulation_info.constraints[:lb_1] = @constraint(m, z >= x_lb*y + y_lb*x - x_lb*y_lb)
    formulation_info.constraints[:lb_2] = @constraint(m, z >= x_ub*y + y_ub*x - x_ub*y_ub)
    formulation_info.constraints[:ub_1] = @constraint(m, z <= x_lb*y + y_ub*x - x_lb*y_ub)
    formulation_info.constraints[:ub_2] = @constraint(m, z <= x_ub*y + y_lb*x - x_ub*y_lb)

    return formulation_info
end


"""
    _build_bilinear_relaxation!(m, x, y, z, x_partition, y_partition)

Build incremental formulation for ``z = xy`` given partition data.
"""
function _build_bilinear_milp_relaxation!(
    m::JuMP.Model,
    x::JuMP.VariableRef,
    y::JuMP.VariableRef,
    z::JuMP.VariableRef,
    x_partition::Vector{<:Real},
    y_partition::Vector{<:Real}
)::FormulationInfo
    
    origin_vs, non_origin_vs = 
        _collect_bilinear_vertices(x_partition, y_partition)
    formulation_info = FormulationInfo()
    num_vars = max(length(x_partition), length(y_partition)) - 1
    

    # add variables
    delta_1 =
        formulation_info.variables[:delta_1] =
            @variable(m, [1:num_vars], lower_bound = 0.0, upper_bound = 1.0)
    delta_2 =
        formulation_info.variables[:delta_2] =
            @variable(m, [1:num_vars], lower_bound = 0.0, upper_bound = 1.0)
    delta_3 =
        formulation_info.variables[:delta_3] =
                @variable(m, [1:num_vars], lower_bound = 0.0, upper_bound = 1.0)
    z_bin = formulation_info.variables[:z_bin] = @variable(m, [1:num_vars], binary = true)

    # add x constraints
    formulation_info.constraints[:x] = @constraint(
        m,
        x ==
        origin_vs[1][1] + sum(
            delta_1[i] * (non_origin_vs[i][1] - origin_vs[i][1]) +
            delta_2[i] * (non_origin_vs[i+1][1] - origin_vs[i][1]) +
            delta_3[i] * (origin_vs[i+1][1] - origin_vs[i][1]) for i = 1:num_vars
        )
    )

    # add y constraints
    formulation_info.constraints[:y] = @constraint(
        m,
        y ==
        origin_vs[1][2] + sum(
            delta_1[i] * (non_origin_vs[i][2] - origin_vs[i][2]) +
            delta_2[i] * (non_origin_vs[i+1][2] - origin_vs[i][2]) +
            delta_3[i] * (origin_vs[i+1][2] - origin_vs[i][2]) for i = 1:num_vars
        )
    )

    # add z constraints
    formulation_info.constraints[:z_bin] = @constraint(
        m,
        z ==
        origin_vs[1][3] + sum(
            delta_1[i] * (non_origin_vs[i][3] - origin_vs[i][3]) +
            delta_2[i] * (non_origin_vs[i+1][3] - origin_vs[i][3]) +
            delta_3[i] * (origin_vs[i+1][3] - origin_vs[i][3]) for i = 1:num_vars
        )
    )

    # add first delta constraint
    formulation_info.constraints[:first_delta] =
        @constraint(m, delta_1[1] + delta_2[1] + delta_3[1] <= 1)

    # add linking constraints between delta_1, delta_2 and z
    formulation_info.constraints[:below_z] =
        @constraint(m, [i = 2:num_vars], delta_1[i] + delta_2[i] + delta_3[i] <= z_bin[i-1])
    formulation_info.constraints[:above_z] =
        @constraint(m, [i = 2:num_vars], z_bin[i-1] <= delta_3[i-1])

    return formulation_info
end 